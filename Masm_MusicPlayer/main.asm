; main.asm
INCLUDE     custom.inc
INCLUDE     music_api.inc
INCLUDE     my_music.inc

.data
filename    BYTE    "1.wav", 0

.code
main PROC
L1:
    INVOKE  PlayMusic,  ADDR filename
    INVOKE  Sleep, 3000
    INVOKE  StopMusic
    INVOKE  Sleep, 3000
    INVOKE  PlayMusic,  ADDR filename
    INVOKE  Sleep, 3000
    INVOKE  PauseMusic
    INVOKE  Sleep, 3000
    INVOKE  ContinueMusic
    INVOKE  Sleep, 3000
    INVOKE  Mute
    INVOKE  Sleep, 3000
    INVOKE  unMute
    INVOKE  Sleep, 3000
    INVOKE  IncreaseVolume
    INVOKE  Sleep, 3000
    INVOKE  DecreaseVolume
    INVOKE  Sleep, 3000
    INVOKE  ForwardMusicTime
    INVOKE  Sleep, 3000
    INVOKE  BackwardMusicTime
    INVOKE  Sleep, 3000
    INVOKE  SetMusicTime, 150
    INVOKE  Sleep, 3000
    INVOKE  StopMusic
    INVOKE  Sleep, 3000
    jmp     L1
    INVOKE  ExitProcess, 0
main ENDP

END main
