const std = @import("std");
const el = @import("eventloop.zig");

const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator(.{});
const EventLoop = el.EventLoop;
const LoopInst = el.LoopInst;

var gpa: GPA = .{};
var alloc: Allocator = gpa.allocator();

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("ucontext.h");
});

fn foo3() callconv(.C) void {
    std.debug.print("foo start\n", .{});
    _ = c.swapcontext(&ctx_foo3, &ctx_bar3);
    std.debug.print("foo end\n", .{});
}

fn bar3() callconv(.C) void {
    std.debug.print("bar start\n", .{});
    _ = c.swapcontext(&ctx_bar3, &ctx_foo3);
    std.debug.print("bar end\n", .{});
}

var ctx_main3: c.ucontext_t = undefined;
var ctx_foo3: c.ucontext_t = undefined;
var ctx_bar3: c.ucontext_t = undefined;

test "context switch c" {
    const stack1: []u8 = try alloc.alloc(u8, 8192);
    const stack2: []u8 = try alloc.alloc(u8, 8192);

    _ = c.getcontext(&ctx_main3);
    _ = c.getcontext(&ctx_foo3);
    _ = c.getcontext(&ctx_bar3);
    
    std.time.sleep(100_000_000);
    
    ctx_foo3.uc_stack.ss_sp = stack1.ptr;
    ctx_foo3.uc_stack.ss_size = stack1.len;
    ctx_foo3.uc_stack.ss_flags = 0;
    ctx_foo3.uc_link = &ctx_bar3;
    c.makecontext(&ctx_foo3, foo3, 0);
    
    ctx_bar3.uc_stack.ss_sp = stack2.ptr;
    ctx_bar3.uc_stack.ss_size = stack2.len;
    ctx_bar3.uc_stack.ss_flags = 0;
    ctx_bar3.uc_link = &ctx_main3;
    c.makecontext(&ctx_bar3, bar3, 0);
    
    std.debug.print("main start\n", .{});
    
    _ = c.swapcontext(&ctx_main3, &ctx_foo3);
    
    std.debug.print("main end\n", .{});
    
}

///////////////////////////////////////////////////////////////////

fn foo() callconv(.C) void {
    std.debug.print("foo start\n", .{});
    inst_foo.switchTo(inst_bar) catch unreachable;
    std.debug.print("foo end\n", .{});
}

fn bar() callconv(.C) void {
    std.debug.print("bar start\n", .{});
    inst_bar.switchTo(inst_foo) catch unreachable;
    std.debug.print("bar end\n", .{});
}

var inst_main: *LoopInst = undefined;
var inst_foo: *LoopInst = undefined;
var inst_bar: *LoopInst = undefined;

test "context switch barebone" {
    inst_main = try LoopInst.createMain(&alloc);
    inst_foo = try LoopInst.createRaw(&alloc, .{ .c_zero = foo }, null);
    inst_bar = try LoopInst.createRaw(&alloc, .{ .c_zero = bar }, null);
    
    try inst_foo.setLink(inst_bar);
    try inst_bar.setLink(inst_main);
    
    std.debug.print("\n", .{});
    std.debug.print("main start\n", .{});
    try inst_main.switchTo(inst_foo);
    std.debug.print("main end\n", .{});
}

///////////////////////////////////////////////////////////////////

fn foo4(ptr: *volatile anyopaque) callconv(.C) void {
    const iptr: *volatile i32 = @ptrCast(@alignCast(ptr));
    std.debug.print("foo4 start: {d}\n", .{iptr.*});
    iptr.* += 1;
    inst_foo4.switchTo(inst_bar4) catch unreachable;
    std.debug.print("foo4 end: {d}\n", .{iptr.*});
}

fn bar4(ptr: *volatile anyopaque) callconv(.C) void {
    const iptr: *volatile i32 = @ptrCast(@alignCast(ptr));
    std.debug.print("bar4 start: {d}\n", .{iptr.*});
    iptr.* += 1;
    inst_bar4.switchTo(inst_foo4) catch unreachable;
    std.debug.print("bar4 end: {d}\n", .{iptr.*});
}

var inst_main4: *LoopInst = undefined;
var inst_foo4: *LoopInst = undefined;
var inst_bar4: *LoopInst = undefined;
var globali: i32 = 0;

test "context switch barebone with arg" {
    inst_main4 = try LoopInst.createMain(&alloc);
    inst_foo4 = try LoopInst.createRaw(&alloc, .{ .c_in = foo4 }, &globali);
    inst_bar4 = try LoopInst.createRaw(&alloc, .{ .c_in = bar4 }, &globali);
    
    try inst_foo4.setLink(inst_bar4);
    try inst_bar4.setLink(inst_main4);
    
    std.debug.print("\n", .{});
    std.debug.print("main4 start\n", .{});
    try inst_main4.switchTo(inst_foo4);
    std.debug.print("main4 end\n", .{});
}

///////////////////////////////////////////////////////////////////

fn foo2() void {
    std.debug.print("foo2 start\n", .{});
    eventloop.yield() catch unreachable;
    std.debug.print("foo2 end\n", .{});
}

fn bar2() !void {
    std.debug.print("bar2 start\n", .{});
    try eventloop.yield();
    std.debug.print("bar2 end\n", .{});
}

var eventloop: *EventLoop = undefined;

test "context switch eventloop" {
    eventloop = try EventLoop.create(&alloc);
    std.debug.print("\n", .{});
    const main_inst = try eventloop.addMain();
    const foo2_inst = try eventloop.addThread(.{ .zero = foo2 }, null);
    const bar2_inst = try eventloop.addThread(.{ .zero_err = bar2 }, null);
    
    _ = main_inst;
    _ = foo2_inst;
    _ = bar2_inst;
    
    std.debug.print("\n", .{});
    std.debug.print("main start\n", .{});
    try eventloop.yield();
    std.debug.print("main mid\n", .{});
    try eventloop.yield();
    std.debug.print("main mid\n", .{});
    try eventloop.yield();
    std.debug.print("main mid\n", .{});
    try eventloop.yield();
    try eventloop.yield();
    try eventloop.yield();
    try eventloop.yield();
    try eventloop.yield();
    std.debug.print("main end\n", .{});
}

///////////////////////////////////////////////////////////////////

fn foo10() void {
    std.debug.print("foo10 start\n", .{});
    eventloop.yield() catch unreachable;
    std.debug.print("foo10 end\n", .{});
}

fn bar10() !void {
    std.debug.print("bar10 start\n", .{});
    try eventloop.yield();
    try eventloop.sleep(100_000); // 100 ms
    std.debug.print("bar10 end\n", .{});
}

fn maz10() !void {
    std.debug.print("maz10 start\n", .{});
    try eventloop.yield();
    std.debug.print("maz10 end\n", .{});
}

var eventloop2: *EventLoop = undefined;


test "context switch eventloop with sleep and join" {
    eventloop2 = try EventLoop.create(&alloc);
    std.debug.print("\n", .{});
    const main_inst = try eventloop2.addMain();
    const foo10_inst = try eventloop2.addThread(.{ .zero = foo10 }, null);
    const bar10_inst = try eventloop2.addThread(.{ .zero_err = bar10 }, null);
    const maz10_inst = try eventloop2.addThread(.{ .zero_err = maz10 }, null);
    
    _ = main_inst;
    
    std.debug.print("\n", .{});
    std.debug.print("main start\n", .{});
    try eventloop2.yield();
    std.debug.print("main mid\n", .{});
    
    _ = try eventloop2.join(maz10_inst);
    std.debug.print("main mid\n", .{});
    _ = try eventloop2.join(bar10_inst);
    std.debug.print("main mid\n", .{});
    _ = try eventloop2.join(foo10_inst);
    std.debug.print("main end\n", .{});
}
