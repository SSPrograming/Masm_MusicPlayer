; music_api.asm 

INCLUDE custom.inc
INCLUDE music_api.inc
INCLUDE util.inc

.data
; ״̬��
Playing         BOOL        FALSE           ; ������״̬
isPlaying       BOOL        FALSE           ; ���ڲ���״̬
hWaveOut        HANDLE      0               ; ��Ƶ����豸���
volume          DWORD       30003000h       ; ������С
muted           BOOL        FALSE           ; ����״̬
totalTime       DWORD       0               ; ������ʱ��
playedTime      DWORD       0               ; �Ѿ����ŵ�ʱ��
haveRead        DWORD       0               ; �Ѿ���ȡ�ģ����飩����

; �ź���
mutexPlaying    HANDLE      0               ; ������״̬������
mutexIsPlaying  HANDLE      0               ; ���ڲ���״̬������
canPlaying      HANDLE      0               ; ����Ȩ

.code

_PlayMusic PROC USES ebx,
    filename: PTR BYTE,             ; �ļ���
    musicType: DWORD                ; ��������
    LOCAL hFile: HANDLE,            ; �ļ����
        waveFormat: WAVEFORMATEX    ; ���ָ�ʽ
    INVOKE  CreateFile,
        ADDR filename,          ; LSCPTR: ָ���ļ�����ָ��
        GENERIC_READ,           ; DWORD: ����ģʽ
        FILE_SHARE_READ,        ; DWORD: ����ģʽ
        NULL,                   ; LPSECURITY_ATTRIBUTES: ָ��ȫ���Ե�ָ��
        OPEN_EXISTING,          ; DWORD: ������ʽ
        FILE_ATTRIBUTE_NORMAL,  ; DWORD: �ļ�����
        NULL                    ; HANDLE: ���ڸ����ļ����
    cmp     eax, INVALID_HANDLE_VALUE
    je      quit
    mov     hFile, eax
    INVOKE  GetMp3Format,
        ADDR filename, 
        ADDR waveFormat
    cmp     eax, FALSE
    je      quit
    mov     ebx, eax

quit:
    ret    
_PlayMusic ENDP

END