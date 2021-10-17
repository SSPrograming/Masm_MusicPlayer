; music_api.asm 

INCLUDE custom.inc
INCLUDE music_api.inc
INCLUDE util.inc

.data
; ����
WAV_HEAD_SIZE = 44

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

; ��ʽ˵��
; WAVEFORMATEX{
;     WORD  wFormatTag,  // ����-��Ƶ��ʽ���ͣ�PCM
;     WORD  nChannels,  // ������
;     DWORD nSamplesPerSec,  // ����Ƶ��
;     DWORD nAvgBytesPerSec,  // ƽ�����ݴ������� = ����Ƶ�� * �����
;     WORD  nBlockAlign,  // ����� = ������ * λ�� / 8
;     WORD  wBitsPerSample,  // λ��
;     WORD  cbSize,  // �����ʽ��Ϣ��PCM��ʽ���Լ���
; };
GetWavFormat PROC USES ecx edx esi edi,
            hFile:                  HANDLE,                 ; �ļ����
            format:                 PTR WAVEFORMATEX        ; ָ��ṹ���ָ��
    LOCAL   buffer[WAV_HEAD_SIZE]:  BYTE                    ; ��ȡ�ļ���Buffer
            realRead:               DWORD                   ; ʵ�ʶ�ȡ���ֽ���
;   RETURN: BOOL 
    lea     esi, buffer
    lea     edx, realRead
    INVOKE  ReadFile,
            hFile,
            esi,                                            ; ��������ַ
            WAV_HEAD_SIZE,
            edx,
            NULL
    cmp     eax, 0
    je      wrong
    mov     eax, realRead
    cmp     eax, WAV_HEAD_SIZE
    jb      wrong
    ; �ṹ�����
    mov     al, 0
    mov     edi, format
    mov     ecx, SIZEOF WAVEFORMATEX
    cld
    rep     stob
    ; �ṹ�����
    add     esi, 20
    mov     edi, format
    mov     ecx, 16
    cld
    rep     movsb
    jmp     right
wrong:
    mov     eax, FALSE
    ret
right:
    mov     eax, TRUE
    ret
GetWavFormat ENDP

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