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
Playing         BOOL        FALSE               ; ������״̬
isPlaying       BOOL        FALSE               ; ���ڲ���״̬
hWaveOut        HANDLE      0                   ; ��Ƶ����豸���
volume          DWORD       30003000h           ; ������С0~F������λΪ������������λΪ������
muted           BOOL        FALSE               ; ����״̬
totalTime       DWORD       0                   ; ������ʱ��
playedTime      DWORD       0                   ; �Ѿ����ŵ�ʱ��
totalRead       DWORD       0                   ; ���֣����飩����
haveRead        DWORD       0                   ; �Ѿ���ȡ�ģ����飩����

; �ź���
mutexPlaying    HANDLE      0                   ; ������״̬������
mutexIsPlaying  HANDLE      0                   ; ���ڲ���״̬������
canPlaying      HANDLE      0                   ; ����Ȩ
mutexRead       HANDLE      0                   ; ���Ž��Ȼ�����

; �ַ�������
wavExtension    BYTE        ".wav", 0           ; wav�ļ���չ��
mp3Extension    BYTE        ".mp3", 0           ; mp3�ļ���չ��
eventDescript   BYTE        "PCM WRITE", 0      ; ��Ϣ����
s1Descript      BYTE        "mutexPlaying", 0   ; �ź���1
s2Descript      BYTE        "mutexIsPlaying", 0 ; �ź���2
s3Descript      BYTE        "CanPlaying", 0     ; �ź���3
s4Descript      BYTE        "mutexRead", 0      ; �ź���4

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
GetWavFormat PROC PRIVATE USES ecx edx esi edi,
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
right:
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
GetWavFormat ENDP

GetWavToBuffer PROC PRIVATE USES ecx edx edi,
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
right:
    mov     eax, realRead
    mov     edi, musicBufferSize
    mov     [edi], eax
    mov     eax, musicBuffer
    ret
freeMemory:
    INVOKE  free, musicBuffer
wrong:
    mov     eax, NULL
    ret
GetWavToBuffer ENDP

GetMinBufferSize PROC PRIVATE USES ebx edx,
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

_PlayMusic PROC PRIVATE USES edx esi edi,
            filename:       PTR BYTE            ; �ļ���
     LOCAL  filenameLength: DWORD,              ; �ļ�������
            musicType:      DWORD,              ; ��������
            hFile:          HANDLE,             ; �ļ����
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
    
    ; �ж��ļ���ʽ
    INVOKE  lstrlen, filename
    cmp     eax, 5
    jb      wrong
    mov     filenameLength, eax
    mov     esi, filename
    add     esi, filenameLength
    sub     esi, 4
    INVOKE  lstrcmp, esi, OFFSET wavExtension
    cmp     eax, 0
    je      isWav
    INVOKE  lstrcmp, esi, OFFSET mp3Extension
    cmp     eax, 0
    je      isMp3
    jmp     wrong
isWav:
    mov     musicType, WAV
    jmp     after
isMp3:
    mov     musicType, MP3
after:

    ; ׼������
    INVOKE  WaitForSingleObject,
            mutexPlaying,
            INFINITE
    mov     Playing, FALSE
    INVOKE  ReleaseSemaphore,
            mutexPlaying,
            1,
            NULL
    INVOKE  WaitForSingleObject,
            canPlaying,
            INFINITE

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
    mov     eax, musicSize
    mov     totalRead, eax
    
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
    cmp     muted, TRUE
    je      ignore
    INVOKE  waveOutSetVolume,
            hWaveOut,
            volume
    cmp     eax, MMSYSERR_NOERROR
    jne     closeEventHandle
ignore:

    ; ���㻺���С
    INVOKE  GetMinBufferSize, waveFormat
    mov     bufferSize, eax
    INVOKE  malloc, bufferSize
    cmp     eax, NULL
    je      closeEventHandle
    mov     buffer, eax

    ; ��ʼ����
    INVOKE  WaitForSingleObject,
            mutexPlaying,
            INFINITE
    mov     Playing, TRUE
    INVOKE  ReleaseSemaphore,
            mutexPlaying,
            1,
            NULL

    ; ���ڲ���
    INVOKE  WaitForSingleObject,
            mutexIsPlaying,
            INFINITE
    mov     isPlaying, TRUE
    INVOKE  ReleaseSemaphore,
            mutexIsPlaying,
            1,
            NULL
    
    INVOKE  WaitForSingleObject,
            mutexRead,
            INFINITE
    mov     haveRead, 0
    INVOKE  ReleaseSemaphore,
            mutexRead,
            1,
            NULL
    ; ѭ����ʼ
L1:
    mov     eax, bufferSize
    mov     realRead, eax
    ; ֡����
    mov     eax, haveRead
    mov     edx, 0
    div     bufferSize
    mul     bufferSize
    push    eax
    INVOKE  WaitForSingleObject,
            mutexRead,
            INFINITE
    pop     eax
    mov     haveRead, eax
    INVOKE  ReleaseSemaphore,
            mutexRead,
            1,
            NULL
    mov     over, FALSE
    ; �����Ƿ���ͣ��䲻ͬ����
    cmp     isPlaying, TRUE
    jne     L4
    ; ����ͣ
    mov     eax, realRead
    add     eax, haveRead
    ; �ж��Ƿ񵽻�����ĩβ
    cmp     eax, musicSize
    jb      L2
    ; ����
    mov     eax, musicSize
    sub     eax, haveRead
    dec     eax
    mov     realRead, eax
L2: ; û��
    mov     esi, musicBuffer
    add     esi, haveRead
    mov     edi, buffer
    mov     ecx, realRead
    cld
    rep     movsb
    ; ���²���
    mov     eax, realRead
    push    eax
    INVOKE  WaitForSingleObject,
            mutexRead,
            INFINITE
    pop     eax
    add     haveRead, eax
    push    eax
    INVOKE  ReleaseSemaphore,
            mutexRead,
            1,
            NULL
    pop     eax
    ; �ж��Ƿ����
    cmp     eax, bufferSize
    jae     L3
    mov     over, TRUE
L3:
    jmp     L5
L4:
    ; ����ͣ
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
    
    ; ���²���
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
    INVOKE  WaitForSingleObject,
            mutexPlaying,
            INFINITE
    mov     Playing, FALSE
    INVOKE  ReleaseSemaphore,
            mutexPlaying,
            1,
            NULL
    mov     playedTime, 0
    mov     totalTime, 0
    INVOKE  WaitForSingleObject,
            mutexRead,
            INFINITE
    mov     haveRead, 0
    INVOKE  ReleaseSemaphore,
            mutexRead,
            1,
            NULL
    mov     totalRead, 0
    INVOKE  free, buffer    
    INVOKE  Sleep, 500
    INVOKE  waveOutClose,
            hWaveOut
    cmp     musicType, WAV
    je      L7
    cmp     musicType, MP3
    je      L8
    jmp     L9
L7:
    INVOKE  free, musicBuffer
    jmp     L9
L8:
    INVOKE  DeleteMp3Buffer, musicBuffer
L9:
    INVOKE  CloseHandle, hEvent
    INVOKE  CloseHandle, hFile

; ��ȷ
right:
    INVOKE  ReleaseSemaphore, 
            canPlaying, 
            1, 
            NULL
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
            filename:   PTR BYTE    ; �ļ���
;   RETURN: BOOL
    ; ��ʼ�����ź���
    cmp     mutexPlaying, 0
    jne     L1
    INVOKE  CreateSemaphore,
            NULL,
            1,
            1,
            OFFSET s1Descript
    cmp     eax, 0
    je      wrong
    mov     mutexPlaying, eax
L1:
    cmp     mutexIsPlaying, 0
    jne     L2
    INVOKE  CreateSemaphore,
            NULL,
            1,
            1,
            OFFSET s2Descript
    cmp     eax, 0
    je      wrong
    mov     mutexIsPlaying, eax
L2:
    cmp     canPlaying, 0
    jne     L3
    INVOKE  CreateSemaphore,
            NULL,
            1,
            1,
            OFFSET s3Descript
    cmp     eax, 0
    je      wrong
    mov     canPlaying, eax
L3:
    cmp     mutexRead, 0
    jne     L4
    INVOKE  CreateSemaphore,
            NULL,
            1,
            1,
            OFFSET s4Descript
    cmp     eax, 0
    je      wrong
    mov     mutexRead, eax
L4:
    INVOKE  CreateThread,
            NULL,
            0,
            _PlayMusic,             ; �̵߳��õĺ�����            
            filename,               ; �̵߳��ô���Ĳ���
            0,
            NULL
    cmp     eax, NULL
    je      wrong
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
PlayMusic ENDP

StopMusic PROC
;   RETURN: BOOL
    INVOKE  WaitForSingleObject,
            mutexPlaying,
            INFINITE
    mov     Playing, FALSE
    INVOKE  ReleaseSemaphore,
            mutexPlaying,
            1,
            NULL
    mov     eax, TRUE
    ret
StopMusic ENDP

PauseMusic PROC
;   RETURN: BOOL
    INVOKE  WaitForSingleObject,
            mutexIsPlaying,
            INFINITE
    mov     isPlaying, FALSE
    INVOKE  ReleaseSemaphore,
            mutexIsPlaying,
            1,
            NULL
    mov     eax, TRUE
    ret
PauseMusic ENDP

ContinueMusic PROC
;   RETURN: BOOL
    INVOKE  WaitForSingleObject,
            mutexIsPlaying,
            INFINITE
    mov     isPlaying, TRUE
    INVOKE  ReleaseSemaphore,
            mutexIsPlaying,
            1,
            NULL
    mov     eax, TRUE
    ret
ContinueMusic ENDP

IncreaseVolume PROC
;   RETURN: BOOL
    cmp     volume, 0F000F000h          ; �Ƿ�ﵽ���ֵ
    je      wrong
    add     volume, 10001000h
    cmp     Playing, TRUE
    jne     L1
    cmp     muted, TRUE
    je      L1
    INVOKE  waveOutSetVolume,
            hWaveOut,
            volume
    cmp     eax, MMSYSERR_NOERROR
    jne     wrong
L1:
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
IncreaseVolume ENDP

DecreaseVolume PROC
;   RETURN: BOOL
    cmp     volume, 00000000h           ; �Ƿ�ﵽ��Сֵ
    je      wrong
    sub     volume, 10001000h
    cmp     Playing, TRUE
    jne     L1
    cmp     muted, TRUE
    je      L1
    INVOKE  waveOutSetVolume,
            hWaveOut,
            volume
    cmp     eax, MMSYSERR_NOERROR
    jne     wrong
L1:
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
DecreaseVolume ENDP

Mute PROC
;   RETURN: BOOL
    cmp     Playing, TRUE
    jne     L1
    INVOKE  waveOutSetVolume,
            hWaveOut,
            0
    cmp     eax, MMSYSERR_NOERROR
    jne     wrong
    mov     muted, TRUE
L1:
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
Mute ENDP

unMute PROC
;   RETURN: BOOL
    cmp     Playing, TRUE
    jne     L1
    INVOKE  waveOutSetVolume,
            hWaveOut,
            volume
    cmp     eax, MMSYSERR_NOERROR
    jne     wrong
    mov     muted, FALSE
L1:
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
unMute ENDP

SetMusicTime PROC,
    time: DWORD     ; ���õĽ�����ʱ�䣬��λ�루s��
;   RETURN: BOOL
    cmp     Playing, TRUE
    jne     wrong
    mov     eax, time
    add     eax, 5
    cmp     eax, totalTime
    ja      wrong
    mov     eax, time
    mul     totalRead
    div     totalTime
    push    eax
    INVOKE  WaitForSingleObject,
            mutexRead,
            INFINITE
    pop     eax
    mov     haveRead, eax
    INVOKE  ReleaseSemaphore,
            mutexRead,
            1,
            NULL
    mov     eax, TRUE
    ret
wrong:
    mov     eax, FALSE
    ret
SetMusicTime ENDP

ForwardMusicTime PROC
    mov     eax, playedTime
    add     eax, 10
    INVOKE  SetMusicTime, eax
    ret
ForwardMusicTime ENDP

BackwardMusicTime PROC
    mov     eax, playedTime
    cmp     eax, 10
    jb      L1
    sub     eax, 10
    jmp     L2
L1:
    mov     eax, 0
L2:
    INVOKE  SetMusicTime, eax
    ret
BackwardMusicTime ENDP

END