; asmfunc.asm
;
; System V AMD64 Calling Convention
; Registers: RDI, RSI, RDX, RCX, R8, R9

bits 64
section .text

global IoOut32  ; void IoOut32(uint16_t addr, uint32_t data);
IoOut32:
    mov dx, di    ; dx = addr
    mov eax, esi  ; eax = data
    out dx, eax
    ret

global IoIn32  ; uint32_t IoIn32(uint16_t addr);
IoIn32:
    mov dx, di    ; dx = addr
    in eax, dx
    ret

global GetCS  ; uint16_t GetCS(void);
GetCS:
    xor eax, eax  ; also clears upper 32 bits of rax
    mov ax, cs
    ret

global LoadIDT  ; void LoadIDT(uint16_t limit, uint64_t offset);
LoadIDT:
    push rbp
    mov rbp, rsp
    sub rsp, 10
    mov [rsp], di  ; limit
    mov [rsp + 2], rsi  ; offset
    lidt [rsp]
    mov rsp, rbp
    pop rbp
    ret

global LoadGDT  ; void LoadGDT(uint16_t limit, uint64_t offset);
LoadGDT:
    push rbp
    mov rbp, rsp
    sub rsp, 10
    mov [rsp], di  ; limit
    mov [rsp + 2], rsi  ; offset
    lgdt [rsp]
    mov rsp, rbp
    pop rbp
    ret

global SetCSSS  ; void SetCSSS(uint16_t cs, uint16_t ss);
SetCSSS:
    push rbp
    mov rbp, rsp
    mov ss, si
    mov rax, .next
    push rdi    ; CS
    push rax    ; RIP
    o64 retf
.next:
    mov rsp, rbp
    pop rbp
    ret

global SetDSAll  ; void SetDSAll(uint16_t value);
SetDSAll:
    mov ds, di
    mov es, di
    mov fs, di
    mov gs, di
    ret

global SetCR3  ; void SetCR3(uint64_t value);
SetCR3:
    mov cr3, rdi
    ret

global GetCR3  ; uint64_t GetCR3();
GetCR3:
    mov rax, cr3
    ret

extern kernel_main_stack
extern KernelMainNewStack

global KernelMain
KernelMain:
    mov rsp, kernel_main_stack + 1024 * 1024
    call KernelMainNewStack
.fin:
    hlt
    jmp .fin

global SwitchContext
SwitchContext:  ; void SwitchContext(void* next_ctx, void* current_ctx);
    mov [rsi + 0x40], rax ; current_ctx.rax = rax
    mov [rsi + 0x48], rbx ; ditto
    mov [rsi + 0x50], rcx
    mov [rsi + 0x58], rdx
    mov [rsi + 0x60], rdi
    mov [rsi + 0x68], rsi

    ; SwitchContext() が呼ばれた時点で rsp のポインタはずれてしまっているので、
    ; 本来保存したいスタックの位置は計算する必要がある (rsp + 8)。
    ; current_ctx.rsp = [rsp + 8]
    lea rax, [rsp + 8]
    mov [rsi + 0x70], rax

    ; current_ctx.rbp = rbp
    mov [rsi + 0x78], rbp

    mov [rsi + 0x80], r8
    mov [rsi + 0x88], r9
    mov [rsi + 0x90], r10
    mov [rsi + 0x98], r11
    mov [rsi + 0xa0], r12
    mov [rsi + 0xa8], r13
    mov [rsi + 0xb0], r14
    mov [rsi + 0xb8], r15

    ; current_ctx.cr3 = cr3
    mov rax, cr3
    mov [rsi + 0x00], rax

    ; rsp の指す先は rip なので、current_ctx.rip = [rsp]
    mov rax, [rsp]
    mov [rsi + 0x08], rax

    ; mov は rflags に対して使えないので、フラグレジスタ rflags の内容を一旦スタックに積む。
    pushfq
    ; すぐ取り出す。 current_ctx.rflags = rflags
    pop qword [rsi + 0x10]

    ; cs の 16bit を (セグメントレジスタは 16 bit 幅しかない) current_ctx.cs に格納する。
    mov ax, cs
    mov [rsi + 0x20], rax

    ; 以下同様。
    mov bx, ss
    mov [rsi + 0x28], rbx
    mov cx, fs
    mov [rsi + 0x30], rcx
    mov dx, gs
    mov [rsi + 0x38], rdx

    ; fxsave は指定された位置に x87 FPU, MMX technology, XMM, MXCSR レジスタの内容を書き出す命令。
    ; 要するに current_ctx.fxsave = fxsave みたいなもん。
    fxsave [rsi + 0xc0]

    ; iret (interruption return) 命令によって next_ctx の内容をレジスタに書き戻すため、
    ; next_ctx の内容をスタックに積む。
    push qword [rdi + 0x28] ; SS
    push qword [rdi + 0x70] ; RSP
    push qword [rdi + 0x10] ; RFLAGS
    push qword [rdi + 0x20] ; CS
    push qword [rdi + 0x08] ; RIP

    ; fx restore
    fxrstor [rdi + 0xc0]

    ; cr3 = next_ctx.cr3
    mov rax, [rdi + 0x00]
    mov cr3, rax

    ; fs = next_ctx.fs
    mov rax, [rdi + 0x30]
    mov fs, ax

    ; gs = next_ctx.gs
    mov rax, [rdi + 0x38]
    mov gs, ax

    mov rax, [rdi + 0x40]
    mov rbx, [rdi + 0x48]
    mov rcx, [rdi + 0x50]
    mov rdx, [rdi + 0x58]
    mov rsi, [rdi + 0x68]
    mov rbp, [rdi + 0x78]
    mov r8,  [rdi + 0x80]
    mov r9,  [rdi + 0x88]
    mov r10, [rdi + 0x90]
    mov r11, [rdi + 0x98]
    mov r12, [rdi + 0xa0]
    mov r13, [rdi + 0xa8]
    mov r14, [rdi + 0xb0]
    mov r15, [rdi + 0xb8]

    ; rdi はここまでの書き戻しの処理でずっと使っていたので、最後に書き戻す。
    mov rdi, [rdi + 0x60]

    ; iret 命令によってスタックに積んだ内容をレジスタに書き戻している。
    ; o64 iret はたぶん iretq と同じもの。
    o64 iret
