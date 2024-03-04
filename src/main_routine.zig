const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("ucontext.h");
});

pub fn Channel(T: type) type {

};

pub const Zigroutine = struct {
    
};
