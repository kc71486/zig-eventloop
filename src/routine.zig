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
    
    backing_threads: []Thread,
    next_routine: ?*RoutineNode = null,
    allocator: *Allocator,
    
    pub fn init(allocator: *Allocator) AllocatorError!This {
        var threads: Thread = try allocator.alloc(Thread, std.Thread.getCpuCount());
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

const RoutineNode = struct {
    next: ?*RoutineNode = null,
    context: Ucontext,
    stack: []u8,
}
