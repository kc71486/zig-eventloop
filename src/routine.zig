const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("ucontext.h");
});

const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;
const AllocatorError = std.mem.Allocator.Error;

const Channel = @import("channel.zig").Channel;

const Ucontext = c.ucontext_t;

pub const Routine = struct {
    const This = @This();
    
    backing_threads: []OSThread,
    next_routine: ?*RoutineNode = null,
    allocator: *Allocator,
    
    pub fn init(allocator: *Allocator) anyerror!This {
        var threads: OSThread = try allocator.alloc(OSThread, try std.Thread.getCpuCount());
        
        // TODO put main thread into slice
        for (&threads) |*thread| {
            thread.* = .{};
        }
        return = .{
            .backing_threads = threads,
            .allocator = allocator,
        };
    }
    pub fn deinit(this: *This) void {
        var allocator = this.allocator;
        allocator.free(this.backing_threads);
    }
    
};

const OSThread = struct {
    thread: Thread = .{},
    routine: ?*RoutineNode = null,
};

const RoutineNode = struct {
    const This = @This();
    
    next: ?*RoutineNode = null,
    context: Ucontext = undefined,
    ismain: bool = false
    stack: []u8,
    
    pub fn init() !This {
        return;
    }
    
    pub fn deinit(this: *This) void {
        _ = this;
    }
}


var curfn: ?*const fn() void;

var waitqueue = linkedqueue;

pub fn addqueue(allocator: Allocator, func: *anyopaque, args: anytype) void {
    node = alloc.create(Node);
    node.* = .{};
    makecontext(node.context, func, args);
    node.context.link = gofun_end;
    waitqueue.push(node);
}

pub fn yield() void {
    var id = Thread.getCurrentId();
    var idx: ?*Thread = null;
    for (threads, 0..) |thread, i| {
        if (id == thread.id) {
            idx = i;
        }
    }
    var orig = context[i];
    waitqueue.tail.next = orig;
    waitqueue.tail = orig;
    context[i] = waitqueue.head;
    waitqueue.head = waitqueue.head.next;
    swapcontext(orig, context[i]);
}

pub fn gofun(ch: *Channel(i32), num: i32) void {
    sleep(10);
    ch.put(num);
} // link to gofun_end

pub fn gofun_end() void {
    while (true) {
        node.deinit();
        // switch to next
    }
}

4 > 5 > 6 > 2

1e
3

test "routine" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();
    a = Channel(int).init(alloc);
    b = Channel(int).init(alloc);
    
    addqueue(alloc, gofun, .{a, 1});
    addqueue(alloc, gofun, .{b, 2});
    addqueue(alloc, gofun, .{a, 3});
    addqueue(alloc, gofun, .{b, 4});
    
    print(a.get());
    print(a.get());
    print(b.get());
    print(b.get());
}
