; music_api.asm 

INCLUDE     custom.inc
INCLUDE     music_api.inc
INCLUDE     my_music.inc
INCLUDE     Winmm.inc
INCLUDELIB  Winmm.lib
INCLUDELIB  msvcrt.lib

malloc PROTO C: DWORD   ; ��̬�����ڴ�
free PROTO C: DWORD     ; ��̬�ͷ��ڴ�

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
    LOCAL   buffer:         PTR BYTE,           ; ���Ż���
            bufferSize:     DWORD,              ; ���Ż����С
            realRead:       DWORD,              ; ʵ�ʲ��Ŵ�С
            over:           DWORD,              ; ������־
            waveHdr:        WAVEHDR             ; ����ͷ
;   RETURN: BOOL

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
    
    ; ��������
    INVOKE  waveOutSetVolume,
            hWaveOut,
            volume
    cmp     eax, MMSYSERR_NOERROR
    jne     closeEventHandle

    ; ���㻺���С
    INVOKE  GetMinBufferSize, waveFormat
    mov     bufferSize, eax
    INVOKE  malloc, bufferSize
    cmp     eax, NULL
    je      closeEventHandle
    mov     buffer, eax

    ; ��ʼ����
    mov     Playing, TRUE

    ; ���ڲ���
    mov     isPlaying, TRUE

    mov     haveRead, 0
    ; ѭ����ʼ
L1:
    mov     eax, bufferSize
    mov     realRead, eax
    mov     over, FALSE
    cmp     isPlaying, TRUE
    jne     L4
    mov     eax, realRead
    add     eax, haveRead
    cmp     eax, musicSize
    jb      L2
    mov     eax, musicSize
    sub     eax, haveRead
    dec     eax
    mov     realRead, eax
L2: 
    mov     esi, musicBuffer
    add     esi, haveRead
    mov     edi, buffer
    mov     ecx, realRead
    cld
    rep     movsb
    mov     eax, realRead
    add     haveRead, eax
    cmp     eax, bufferSize
    jae     L3
    mov     over, TRUE
L3:
    jmp     L5
L4:
    mov     al, 0
    mov     edi, buffer
    mov     ecx, realRead
    cld
    rep     stosb
L5:
    ; ��װ
    mov     eax, buffer
    mov     waveHdr.lpData, eax
    mov     eax, realRead
    mov     waveHdr.dwBufferLength, eax
    mov     waveHdr.dwBytesRecorded, 0
    mov     waveHdr.dwUser, NULL
    mov     waveHdr.dwFlags, 0
    mov     waveHdr.dwLoops, 1
    mov     waveHdr.lpNext, NULL
    mov     waveHdr.Reserved, NULL

    ; ��������
    lea     esi, waveHdr
    INVOKE  waveOutPrepareHeader,
            hWaveOut,
            esi,
            SIZEOF WAVEHDR
    cmp     eax, MMSYSERR_NOERROR
    jne     L6
    INVOKE  waveOutWrite,
            hWaveOut,
            esi,
            SIZEOF WAVEHDR
    cmp     eax, MMSYSERR_NOERROR
    jne     L6
    INVOKE  WaitForSingleObject,
            hEvent,
            INFINITE
    mov     eax, haveRead
    mov     edx, 0
    mul     totalTime
    div     musicSize
    mov     playedTime, eax
    cmp     Playing, FALSE
    je      L6
    cmp     over, TRUE
    je      L6
    jmp     L1
L6:
    ; ѭ������
    mov     Playing, FALSE
    mov     playedTime, 0
    mov     totalTime, 0
    INVOKE  free, buffer    
    INVOKE  Sleep, 500
    INVOKE  waveOutClose,
            hWaveOut
    INVOKE  free, musicBuffer    
    INVOKE  CloseHandle, hEvent
    INVOKE  CloseHandle, hFile

; ��ȷ
right:
    mov     eax, TRUE
    ret
; ����
closeEventHandle:
    INVOKE  CloseHandle, hEvent
freeMemory:
    INVOKE  free, musicBuffer
closeFileHandle:
    INVOKE  CloseHandle, hFile
wrong:
    mov     eax, FALSE
    ret    
_PlayMusic ENDP

PlayMusic PROC USES ebx,
    filename: PTR BYTE
    INVOKE  _PlayMusic, filename, WAV
    ret
PlayMusic ENDP

END