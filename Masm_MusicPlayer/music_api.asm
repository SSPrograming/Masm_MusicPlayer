; music_api.asm 

INCLUDE custom.inc
INCLUDE music_api.inc
INCLUDE util.inc
INCLUDE c.inc

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

; �ַ�������
eventDescript   BYTE        "PCM WRITE", 0  ; ��Ϣ����

.code

; ��ʽ˵��
; WAVEFORMATEX {
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
    LOCAL   buffer[WAV_HEAD_SIZE]:  BYTE,                   ; ��ȡ�ļ���Buffer
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
    rep     stosb
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

GetWavToBuffer PROC USES ecx edx edi,
            hFile:              HANDLE,         ; �ļ����
            musicBufferSize:    PTR DWORD       ; ָ�����ֻ�������С��ָ��
    LOCAL   musicSize:          DWORD,          ; �����ļ���С
            musicBuffer:        PTR BYTE,       ; ָ�����ֻ�������ָ��
            realRead:           DWORD           ; ʵ�ʶ�ȡ���ֽ���
;   RETURN: PTR BYTE
    INVOKE  GetFileSize,
            hFile,
            NULL 
    cmp     eax, INVALID_FILE_SIZE
    je      wrong
    mov     musicSize, eax
    INVOKE  malloc, musicSize                   ; ��̬�����ڴ�
    cmp     eax, NULL
    je      wrong
    mov     musicBuffer, eax
    ; �ڴ����
    mov     al, 0
    mov     edi, musicBuffer
    mov     ecx, musicSize
    cld
    rep     stosb
    ; ��ȡ�ļ�
    lea     edx, realRead
    sub     musicSize, WAV_HEAD_SIZE
    INVOKE  ReadFile,
            hFile,
            musicBuffer,
            musicSize,
            edx,
            NULL
    cmp     eax, 0
    je      freeMemory
    mov     eax, realRead
    cmp     eax, musicSize
    jb      freeMemory
    jmp     right
freeMemory:
    INVOKE  free, musicBuffer
wrong:
    mov     eax, NULL
    ret
right:
    mov     eax, realRead
    mov     edi, musicBufferSize
    mov     [edi], eax
    mov     eax, musicBuffer
    ret
GetWavToBuffer ENDP

GetMinBufferSize PROC USES ebx edx,
            format:     WAVEFORMATEX        ; �ļ���ʽ
;   RETURN: DWORD
    mov     eax, 64
    mul     format.nChannels
    mul     format.wBitsPerSample
    mul     format.nSamplesPerSec
    mov     edx, 0
    mov     ebx, 11025
    div     ebx
    ret
GetMinBufferSize ENDP

_PlayMusic PROC USES edx esi edi,
            filename:       PTR BYTE,           ; �ļ���
            musicType:      DWORD               ; ��������
    LOCAL   hFile:          HANDLE,             ; �ļ����
            musicBuffer:    PTR BYTE,           ; ���ֻ�����
            musicSize:      DWORD,              ; ���ִ�С
            waveFormat:     WAVEFORMATEX,       ; ���ָ�ʽ
            hEvent:         HANDLE              ; �ص��¼����

    ; ׼������
    mov     Playing, FALSE

    ; �����ļ�
    INVOKE  CreateFile,
            filename,               
            GENERIC_READ,           
            FILE_SHARE_READ,        
            NULL,                  
            OPEN_EXISTING,          
            FILE_ATTRIBUTE_NORMAL,  
            NULL                    
    cmp     eax, INVALID_HANDLE_VALUE
    je      wrong
    mov     hFile, eax

    ; ������Ƶ�ļ�
    cmp     musicType, WAV
    je      wav
    cmp     musicType, MP3
    je      mp3
    jmp     closeFileHandle
wav:
    ; ��ȡ��Ƶ���ʽ
    lea     edi, waveFormat
    INVOKE  GetWavFormat, hFile, edi
    cmp     eax, FALSE
    je      closeFileHandle
    ; ��ȡ��Ƶ����
    lea     edi, musicSize
    INVOKE  GetWavToBuffer, hFile, edi
    cmp     eax, NULL
    je      closeFileHandle
    mov     musicBuffer, eax
    jmp     next
mp3:
    ; ��ȡ��Ƶ���ʽ
    lea     edi, waveFormat
    INVOKE  GetMp3Format, filename, edi
    cmp     eax, FALSE
    je      closeFileHandle
    ; ��ȡ��Ƶ����
    lea     edi, musicSize
    INVOKE  DecodeMp3ToBuffer, hFile, edi
    cmp     eax, NULL
    je      closeFileHandle
    mov     musicBuffer, eax     
next:
    mov     eax, musicSize
    mov     edx, 0
    div     waveFormat.nAvgBytesPerSec
    mov     totalTime, eax
    
    ; �����ص��¼�
    INVOKE  CreateEvent,
            NULL,
            FALSE,
            FALSE,
            ADDR eventDescript
    cmp     eax, NULL
    je      freeMemory
    mov     hEvent, eax

    ; ����Ƶ
    lea     esi, waveFormat
    INVOKE  waveOutOpen,
            OFFSET hWaveOut,
            WAVE_MAPPER,
            esi,
            hEvent,
            NULL,
            CALLBACK_EVENT
    cmp     eax, MMSYSERR_NOERROR
    jne     closeEventHandle
    jmp     right


closeEventHandle:
    INVOKE  CloseHandle, hEvent
freeMemory:
    INVOKE  free, musicBuffer
closeFileHandle:
    INVOKE  CloseHandle, hFile
wrong:
    mov     eax, FALSE
    ret    
right:
    mov     eax, TRUE
    ret
_PlayMusic ENDP

PlayMusic PROC USES ebx,
    filename: PTR BYTE
    INVOKE  _PlayMusic, filename, WAV
    ret
PlayMusic ENDP

END