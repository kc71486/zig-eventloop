const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("ucontext.h");
});

const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;
const Ucontext = c.ucontext_t;

const TheFPointer = *const fn () callconv(.C) void;

pub var STACKSIZE: u32 = 65536;
pub var EVENTLINIT: u32 = 8;

pub const EventLoop = struct {
    const This = @This();
    
    allocator: *Allocator,
    instances: []*LoopInst,
    size: u32 = 0,
    curidx: u32 = 0,
    curtid: u32 = 0,
    cleanup_instance: *LoopInst,
    
    // create EventLoop object
    pub fn create(alloc: *Allocator) !*This {
        const this: *This = try alloc.create(This);
        this.* = .{
            .allocator = alloc,
            .instances = try alloc.alloc(*LoopInst, 8),
            .cleanup_instance = try LoopInst.createRaw(alloc, .{ .c_in = fn_exit }, this),
            .size = 0,
            .curidx = 0,
            .curtid = 0,
        };
        this.cleanup_instance.tid = 0;
        this.curtid = 1;
        return this;
    }
    
    // destroy EventLoop object
    pub fn destroy(this: *This) void {
        this.allocator.free(this.instances);
        this.allocator.destroy(this);
    }
    
    // add an instance of concurrent (but not parallel) thread
    pub fn addThread(this: *This, func: FunctionUnion, arg: ?*anyopaque) !*LoopInst {
        if (this.size >= this.instances.len) {
            return error.MaxInstanceReached;
        }
        var newinst: *LoopInst = try LoopInst.createFunc(this.allocator, func, arg);
        try newinst.setLink(this.cleanup_instance);
        
        this.instances[this.size] = newinst;
        this.size += 1;
        newinst.tid = this.curtid;
        this.curtid += 1;
        return this.instances[this.size - 1];
    }
    
    // add an instance of concurrent (but not parallel) thread
    pub fn addMain(this: *This) !*LoopInst {
        if (this.size >= this.instances.len) {
            return error.MaxInstanceReached;
        }
        var newinst: *LoopInst = try LoopInst.createMain(this.allocator);
        
        this.instances[this.size] = newinst;
        this.size += 1;
        newinst.tid = this.curtid;
        this.curtid += 1;
        return this.instances[this.size - 1];
    }
    
    // yields the current thread potentially allowing other threads to run
    pub fn yield(this: *This) !void {
        const oldinst: *LoopInst = this.instances[this.curidx];
        this.setNewCuridx(this.curidx + 1);
        const newinst: *LoopInst = this.instances[this.curidx];
        try oldinst.switchTo(newinst);
    }
    
    // Waits for the thread to complete, then destroy any created resources
    // returns what joined target return or null if not exist
    pub fn join(this: *This, target: *LoopInst) !?*anyopaque {
        const curinst: *LoopInst = this.instances[this.curidx];
        target.info.join_ret_inst = curinst;
        curinst.info.status = .join;
        
        this.setNewCuridx(this.curidx + 1);
        const newinst: *LoopInst = this.instances[this.curidx];
        try curinst.switchTo(newinst);
        
        return curinst.info.join_retval;
    }
    
    // Waits for the thread to complete, then destroy any created resources
    pub fn sleep(this: *This, microseconds: i64) !void {
        const ms: i64 = if (microseconds >= 0) microseconds else 0;
        this.instances[this.curidx].info.sleep_end_time = std.time.microTimestamp() + ms;
        this.instances[this.curidx].info.status = .sleep;
    }
    
    // decides what next instance should be
    // nextindex indicates the primary choice
    fn setNewCuridx(this: *This, nextindex: u32) void {
        std.debug.print("curidx start: {}, {}\n", .{this.curidx, this.size});
        this.curidx = nextindex % this.size;
        std.debug.print("curidx mid: {}\n", .{this.curidx});
        while (true) {
            const inst: *LoopInst = this.instances[this.curidx];
            if (inst.info.status == .run) {
                break;
            }
            if (inst.info.status == .sleep and std.time.microTimestamp() >= inst.info.sleep_end_time) {
                inst.info.status = .run;
                break;
            }
            this.curidx = (this.curidx + 1) % this.size;
        }
        std.debug.print("curidx end: {}\n", .{this.curidx});
    }
    
    // every function will end up here
    fn fn_exit(ptr: *anyopaque) callconv(.C) void {
        const this: *This = @ptrCast(@alignCast(ptr));
        if (this.size == 0)
            unreachable;
        while (true) {
            // actual _exit start place
            const inst: *LoopInst = this.instances[this.curidx];
            if (inst.info.join_ret_inst) |join_inst| {
                join_inst.info.join_retval = if (inst.main_func) |main_fn|
                    main_fn.ret
                else
                    null;
                join_inst.info.status = .run;
            }
            
            inst.destroy(this.allocator);
            const curidx = this.curidx;
            const size = this.size;
            std.mem.copyForwards(*LoopInst, this.instances[curidx..size], this.instances[(curidx + 1)..size]);
            this.size -= 1;
            this.setNewCuridx(this.curidx);
            if (this.size == 0)
                break;
            
            this.cleanup_instance.switchTo(this.instances[this.curidx]) catch unreachable;
        }
    }
};

pub const ThreadWrapper = struct {
    ptr: LoopInst,
    alive: bool,
};

// various function type for EntryFunction
pub const EntryUnion = union(enum) {
    c_zero: *const fn () callconv(.C) void,
    c_in: *const fn (*anyopaque) callconv(.C) void,
};

// various function type for MainFunction
pub const FunctionUnion = union(enum) {
    const This = @This();
    
    zero: *const fn () void,
    in: *const fn (*anyopaque) void,
    out: *const fn () *anyopaque,
    inout: *const fn (*anyopaque) *anyopaque,
    zero_err: *const fn () anyerror!void,
    in_err: *const fn (*anyopaque) anyerror!void,
    out_err: *const fn () anyerror!*anyopaque,
    inout_err: *const fn (*anyopaque) anyerror!*anyopaque,
    c_zero: *const fn () callconv(.C) void,
    c_in: *const fn (*anyopaque) callconv(.C) void,
    c_out: *const fn () callconv(.C) *anyopaque,
    c_inout: *const fn (*anyopaque) callconv(.C) *anyopaque,
};

pub const ThreadStatus = enum {
    run,
    sleep,
    join,
};

pub const EntryFunction = struct {
    func: EntryUnion,
    arg: ?*anyopaque = null,
    stack: []u8,
    
    pub inline fn getFPointer(this: EntryFunction) TheFPointer {
        switch (this.func) {
            .c_zero => |funct| return funct,
            .c_in => |funct| return @ptrCast(funct),
        }
    }
};

pub const MainFunction = struct {
    func: FunctionUnion,
    arg: ?*anyopaque = null,
    ret: ?*anyopaque = null,
};

pub const ThreadInfo = struct {
    status: ThreadStatus = .run,
    
    // sleep_end_time
    sleep_end_time: i64 = 0,
    
    // in a.join(b), b.join_ret_inst = a
    join_ret_inst: ?*LoopInst = null,
    
    // what join() returns
    join_retval: ?*anyopaque = null,
};

pub const LoopInst = struct {
    const This = @This();
    
    context: Ucontext,
    entry_func: ?*EntryFunction,
    main_func: ?*MainFunction,
    link: ?*LoopInst = null,
    tid: u32 = 0,
    info: ThreadInfo = .{},
    
    // create a thread with a default entry function
    // if the function doesn't accept argument, arg will be ignored
    pub fn createFunc(alloc: *Allocator, func: FunctionUnion, arg: ?*anyopaque) !*This {
        const this: *This = try alloc.create(This);
        this.* = .{
            .context = undefined,
            .entry_func = try alloc.create(EntryFunction),
            .main_func = try alloc.create(MainFunction),
        };
        
        const retval = c.getcontext(&this.context);
        if (retval != 0)
            return error.Cgetcontext;
        
        this.entry_func.?.* = .{
            .func = .{ .c_in = &fn_entry },
            .arg = this,
            .stack = try alloc.alloc(u8, STACKSIZE),
        };
        
        this.main_func.?.* = .{
            .func = func,
            .arg = arg,
        };
        
        const entry_fn: *EntryFunction = this.entry_func.?;
        this.context.uc_stack.ss_sp = entry_fn.stack.ptr;
        this.context.uc_stack.ss_size = entry_fn.stack.len;
        this.context.uc_stack.ss_flags = 0;
        c.makecontext(&this.context, entry_fn.getFPointer(), 1, entry_fn.arg.?);
        return this;
    }
    
    // create a thread without entry function
    // requires function with c calling convention and no return value
    pub fn createRaw(alloc: *Allocator, func: EntryUnion, arg: ?*anyopaque) !*This {
        const this: *LoopInst = try alloc.create(LoopInst);
        this.* = .{
            .context = undefined,
            .entry_func = try alloc.create(EntryFunction),
            .main_func = null,
        };
        
        const retval = c.getcontext(&this.context);
        if (retval != 0)
            return error.Cgetcontext;
        
        this.entry_func.?.* = .{
            .func = func,
            .arg = arg,
            .stack = try alloc.alloc(u8, STACKSIZE),
        };
        
        const entry_fn: *EntryFunction = this.entry_func.?;
        this.context.uc_stack.ss_sp = entry_fn.stack.ptr;
        this.context.uc_stack.ss_size = entry_fn.stack.len;
        this.context.uc_stack.ss_flags = 0;
        switch (func) {
            .c_zero => c.makecontext(&this.context, entry_fn.getFPointer(), 0),
            .c_in => c.makecontext(&this.context, entry_fn.getFPointer(), 1, entry_fn.arg.?),
        }
        return this;
    }
    
    // create a thread that doesn't bind with any function. Act like main thread.
    // If main thread leave, all other thread will be discarded
    pub fn createMain(alloc: *Allocator) !*This {
        const this = try alloc.create(This);
        this.* = .{
            .context = undefined,
            .entry_func = null,
            .main_func = null,
        };
        
        const retval = c.getcontext(&this.context);
        if (retval != 0)
            return error.Cgetcontext;
        
        return this;
    }
    
    // destroy LoopInst object
    pub fn destroy(this: *This, alloc: *Allocator) void {
        if (this.entry_func) |entry_fn| {
            
            alloc.free(entry_fn.stack);
            alloc.destroy(entry_fn);
        }
        if (this.main_func) |main_fn| {
            alloc.destroy(main_fn);
        }
        alloc.destroy(this);
    }
    
    // getcontext with better name, 
    pub fn storeRegState(this: *This) !void {
        const retval = c.getcontext(&this.context);
        if (retval != 0) {
            return error.storeState;
        }
    }
    
    // setcontext with better name
    pub fn retrieveRegState(this: *This) !void {
        const retval = c.setcontext(&this.context);
        if (retval != 0) {
            return error.retrieveState;
        }
    }
    
    // content switch with better name
    pub fn switchTo(this: *This, dst: *This) !void {
        const retval = c.swapcontext(&this.context, &dst.context);
        if (retval != 0) {
            return error.SwapContext;
        }
    }
    
    // set link target, will jump to linked target after finishing current thread
    // thread without function attached cannot link to other target
    pub fn setLink(this: *This, target: *This) !void {
        if (this.entry_func == null) {
            return error.emptyEntry;
        }
        this.link = target;
        this.context.uc_link = &target.context;
        const entry_fn: *EntryFunction = this.entry_func.?;
        switch (entry_fn.func) {
            .c_zero => c.makecontext(&this.context, entry_fn.getFPointer(), 0),
            .c_in => c.makecontext(&this.context, entry_fn.getFPointer(), 1, entry_fn.arg.?),
        }
    }
    
    // default entry function
    // every context goes into this function before entering dedicated function
    fn fn_entry(ptr: *anyopaque) callconv(.C) void {
        const this: *This = @ptrCast(@alignCast(ptr));
        if (this.main_func == null) {
            std.debug.print("error: empty main_func in entry {d}\n", .{this.tid});
            return;
        }
        std.debug.print("enter entry {d}\n", .{this.tid});
        const main_fn = this.main_func.?;
        switch (main_fn.func) {
            .zero => |funct| funct(),
            .in => |funct| funct(main_fn.arg.?),
            .out => |funct| main_fn.ret = funct(),
            .inout => |funct| main_fn.ret = funct(main_fn.arg.?),
            .zero_err => |funct| funct() catch unreachable,
            .in_err => |funct| funct(main_fn.arg.?) catch unreachable,
            .out_err => |funct| main_fn.ret = funct() catch unreachable,
            .inout_err => |funct| main_fn.ret = funct(main_fn.arg.?) catch unreachable,
            .c_zero => |funct| funct(),
            .c_in => |funct| funct(main_fn.arg.?),
            .c_out => |funct| main_fn.ret = funct(),
            .c_inout => |funct| main_fn.ret = funct(main_fn.arg.?),
        }
        std.debug.print("leave entry {d}\n", .{this.tid});
    }
};
