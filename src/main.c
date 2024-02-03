#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <ucontext.h>

void fun1();
void fun2();

ucontext_t main_ctx;
ucontext_t fun1_ctx;
ucontext_t fun2_ctx;

int main() {
    char stack1[8192];
    char stack2[8192];

    getcontext(&main_ctx);
    getcontext(&fun1_ctx);
    getcontext(&fun2_ctx);
    
    usleep(1000);
    
    fun1_ctx.uc_stack.ss_sp = stack1;
    fun1_ctx.uc_stack.ss_size = 8192;
    fun1_ctx.uc_stack.ss_flags = 0;
    fun1_ctx.uc_link = &fun2_ctx;
    makecontext(&fun1_ctx, fun1, 0);
    
    fun2_ctx.uc_stack.ss_sp = stack2;
    fun2_ctx.uc_stack.ss_size = 8192;
    fun2_ctx.uc_stack.ss_flags = 0;
    fun2_ctx.uc_link = &main_ctx;
    makecontext(&fun2_ctx, fun2, 0);

    swapcontext(&main_ctx, &fun1_ctx);
    
    printf("main end\n");
    return 0;
}

void fun1() {
    printf("fun1() start\n");
    swapcontext(&fun1_ctx, &fun2_ctx);
    printf("fun1() end\n");
}
void fun2() {
    printf("fun2() start\n");
    swapcontext(&fun2_ctx, &fun1_ctx);
    printf("fun2() end\n");
}
