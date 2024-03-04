const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("ucontext.h");
});
const struct_routine = @import("routine.zig");

const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;
const AllocatorError = std.mem.Allocator.Error;

pub fn Channel(comptime T: type) type {
    return struct {
        const This = @This();
        const Node = ChannelNode(T);
        
        head: ?*Node = null,
        tail: ?*Node = null,
        lock_head: Mutex = .{},
        lock_tail: Mutex = .{},
        allocator: *Allocator,
        
        pub fn init(allocator: *Allocator) This {
             return .{
                .allocator = allocator,
             };
        }
        
        pub fn deinit(this: *This) void {
            while (this.head) |head| {
                this.head = head.next;
                this.allocator.destroy(head);
            }
        }
        
        pub fn put(this: *This, element: T) AllocatorError!void {
            const newnode = try this.allocator.create(Node);
            newnode.* = .{
                .element = element,
            };
            
            // I don't think it will deadlock because:
            //   lock_tail -> lock_head occurs when put empty list
            //   lock_head -> lock_tail occurs when get non-empty list
            // so to make lock_tail -> lock_head happen:
            //   put is already locked, get will always skip if statement
            //   because this.tail == this.head == null and get cannot modify anything before head != null
            this.lock_tail.lock();
            defer this.lock_tail.unlock();
            
            if (this.tail) |tail| {
                tail.next = newnode;
                this.tail = newnode;
            } else {
                this.lock_head.lock();
                defer this.lock_head.unlock();
                
                this.head = newnode;
                this.tail = newnode;
            }
        }
        
        pub fn get(this: *This) T {
            // hang while empty
            while (true) {
                this.lock_head.lock();
                defer this.lock_head.unlock();
                
                if (this.head) |head| {
                    this.lock_tail.lock();
                    defer this.lock_tail.unlock();
                    
                    const ret: T = head.element;
                    this.head = head.next;
                    if (this.head == null) {
                        this.tail = null;
                    }
                    this.allocator.destroy(head);
                    return ret;
                }
            }
        }
    };
}

fn ChannelNode(comptime T: type) type {
    return struct {
        next: ?*ChannelNode(T) = null,
        element: T,
    };
}

test Channel {
    const expect = std.testing.expect;
    var testalloc = std.testing.allocator;
    
    var channel = Channel(i64).init(&testalloc);
    defer channel.deinit();
    
    try channel.put(1);
    try channel.put(2);
    try channel.put(3);
    try expect(channel.get() == 1);
    try expect(channel.get() == 2);
    try channel.put(4);
    try expect(channel.get() == 3);
}
