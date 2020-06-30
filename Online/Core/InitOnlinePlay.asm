################################################################################
# Address: 0x8016e748 # StartMelee before the standard Slippi stuff runs
################################################################################

.include "Common/Common.s"
.include "Online/Online.s"

.set REG_ODB_ADDRESS, 27
.set REG_RXB_ADDRESS, 26
.set REG_SSRB_ADDR, 25
.set REG_MSRB_ADDR, 24

# Run replaced code
branchl r12, 0x802254B8

backup

# Ensure that this is an online match
getMinorMajor r3
cmpwi r3, SCENE_ONLINE_IN_GAME
bne GECKO_EXIT

################################################################################
# Initialize Online Data Buffers
################################################################################

li r3, ODB_SIZE
branchl r12, HSD_MemAlloc
mr REG_ODB_ADDRESS, r3
li r4, ODB_SIZE
branchl r12, Zero_AreaLength

stw REG_ODB_ADDRESS, OFST_R13_ODB_ADDR(r13)

# Indicate that the first frame is frame 1
li r3, 1
stw r3, ODB_FRAME(REG_ODB_ADDRESS)

# Store location to game complete handler
bl FN_HandleGameCompleted
mflr r3
stw r3, ODB_FN_HANDLE_GAME_OVER_ADDR(REG_ODB_ADDRESS)

# Create buffers for EXI data transfer. These buffers are split up because
# EXI buffers must be 32-byte aligned to work
li r3, TXB_SIZE
branchl r12, HSD_MemAlloc
stw r3, ODB_TXB_ADDR(REG_ODB_ADDRESS)

li r3, RXB_SIZE
branchl r12, HSD_MemAlloc
stw r3, ODB_RXB_ADDR(REG_ODB_ADDRESS)
mr REG_RXB_ADDRESS, r3

# Prepare buffer for requesting savestate actions from Dolphin
li r3, SSRB_SIZE
branchl r12, HSD_MemAlloc
mr REG_SSRB_ADDR, r3
stw REG_SSRB_ADDR, ODB_SAVESTATE_SSRB_ADDR(REG_ODB_ADDRESS)

# Prepare buffer for ASM side savestates
li r3, SSCB_SIZE
branchl r12, HSD_MemAlloc
stw r3, ODB_SAVESTATE_SSCB_ADDR(REG_ODB_ADDRESS)
li r4, SSCB_SIZE
branchl r12, Zero_AreaLength

li r4, 0
stb r4, SSCB_WRITE_INDEX(r3)

li r4, ROLLBACK_MAX_FRAME_COUNT
stb r4, SSCB_SSDB_COUNT(r3)

# Write the locations that will be preserved through a savestate
stw REG_ODB_ADDRESS, SSRB_ODB_ADDR(REG_SSRB_ADDR)
li r3, ODB_SIZE
stw r3, SSRB_ODB_SIZE(REG_SSRB_ADDR)
stw REG_RXB_ADDRESS, SSRB_RXB_ADDR(REG_SSRB_ADDR)
li r3, RXB_SIZE
stw r3, SSRB_RXB_SIZE(REG_SSRB_ADDR)
lwz r3, ODB_SAVESTATE_SSCB_ADDR(REG_ODB_ADDRESS)
stw r3, SSRB_SSCB_ADDR(REG_SSRB_ADDR)
li r3, SSCB_SIZE
stw r3, SSRB_SSCB_SIZE(REG_SSRB_ADDR)
li r3, 0 # Write terminator
stw r3, SSRB_TERMINATOR(REG_SSRB_ADDR)

################################################################################
# Prepare match characters, ports, and RNG
################################################################################
# Get match state info
li r3, 0
branchl r12, FN_LoadMatchState
mr REG_MSRB_ADDR, r3

# Prepare player indices
lbz r3, -0x5108(r13) # Grab the 1p port in use
stb r3, ODB_INPUT_SOURCE_INDEX(REG_ODB_ADDRESS)
lbz r3, MSRB_LOCAL_PLAYER_INDEX(REG_MSRB_ADDR)
stb r3, ODB_LOCAL_PLAYER_INDEX(REG_ODB_ADDRESS)
lbz r3, MSRB_REMOTE_PLAYER_INDEX(REG_MSRB_ADDR)
stb r3, ODB_ONLINE_PLAYER_INDEX(REG_ODB_ADDRESS)

# Copy over RNG Offset
lwz r3, MSRB_RNG_OFFSET(REG_MSRB_ADDR)
stw r3, ODB_RNG_OFFSET(REG_ODB_ADDRESS)

# Write RNG offset to seed such that the start seed matches. Without this I
# noticed some desyncs on FD
lis r4, 0x804D
stw r3, 0x5F90(r4) # overwrite seed

# Copy match struct
mr r3, r31
addi r4, REG_MSRB_ADDR, MSRB_GAME_INFO_BLOCK
li r5, MATCH_STRUCT_LEN
branchl r12, memcpy

################################################################################
# Set up number of delay frames
################################################################################
lbz r3, MSRB_DELAY_FRAMES(REG_MSRB_ADDR)
cmpwi r3, MIN_DELAY_FRAMES
blt DELAY_FRAMES_MIN_LIMIT
cmpwi r3, MAX_DELAY_FRAMES
bgt DELAY_FRAMES_MAX_LIMIT
b SET_DELAY_FRAMES

DELAY_FRAMES_MIN_LIMIT:
li r3, MIN_DELAY_FRAMES
b SET_DELAY_FRAMES

DELAY_FRAMES_MAX_LIMIT:
li r3, MAX_DELAY_FRAMES

SET_DELAY_FRAMES:
stb r3, ODB_DELAY_FRAMES(REG_ODB_ADDRESS)

################################################################################
# Initialize everyone to UCF
################################################################################
# Back up the controller settings
lwz r3, -ControllerFixOptions(rtoc)
stw r3, ODB_CF_OPTION_BACKUP(REG_ODB_ADDRESS)

# Init everyone to UCF
load r3, 0x01010101
stw r3, -ControllerFixOptions(rtoc)

################################################################################
# Clear A inputs to prevent transformation
################################################################################
# This is kind of jank but it will prevent Slippi from trying to flip the
# character in the recording game info block. It will also prevent a
# sheik -> zelda or zelda -> sheik transformation. This does every port because
# otherwise it might be possible for someone to play online with two controllers
# plugged in to start the opponent as the wrong character
li r5, 0

LOOP_CLEAR_INPUTS_START:
load r3, 0x804c20bc
mulli	r4, r5, 68
add r3, r3, r4
li r4, 0
stw r4, 0x0(r3)

addi r5, r5, 1
cmpwi r5, 4
blt LOOP_CLEAR_INPUTS_START

################################################################################
# Initialize RNG Function for Online Games
################################################################################

# Create GObj
li r3, 4 # GObj Type (4 is the player type, this should ensure it runs before any player animations)
li r4, 7 # On-Pause Function (dont run on pause)
li r5, 0 # some type of priority
branchl r12, GObj_Create

#Create Proc
bl FN_SyncRNG
mflr r4 # Function
li r5, 0 # Priority
branchl	r12, GObj_AddProc

# Set client pause callback
bl  ClientPause
mflr  r3
stw r3,0x40(r31)

# Init pause
li  r3,0
stb r3, OFST_R13_ISPAUSE (r13)

b GECKO_EXIT

################################################################################
# Routine: SyncRNG
# ------------------------------------------------------------------------------
# Description: Syncs RNG when playing online
################################################################################

FN_SyncRNG:
blrl

loadGlobalFrame r3
rlwinm r4, r3, 16, 0xFFFFFFFF # Rotate left 16 bits for better RNG differences?

# Add RNG offset such that games are not always the same. Without this, for
# example, Pokemon would always go to the same transformation
lwz r3, OFST_R13_ODB_ADDR(r13) # ODB address
lwz r3, ODB_RNG_OFFSET(r3)
add r4, r4, r3

lis r3, 0x804D
stw r4, 0x5F90(r3) # overwrite random seed

blr

################################################################################
# Routine: HandleGameCompleted
# ------------------------------------------------------------------------------
# Description: Function called when game if confirmed over (no more rollbacks)
################################################################################
FN_HandleGameCompleted:
blrl

.set REG_ODB_ADDRESS, 4

lwz REG_ODB_ADDRESS, OFST_R13_ODB_ADDR(r13) # data buffer address

# Restore controller fix states
lwz r3, ODB_CF_OPTION_BACKUP(REG_ODB_ADDRESS)
stw r3, -ControllerFixOptions(rtoc)

# TODO: Write to EXI that game has ended to confirm there was no desync?

blr

################################################################################
# Routine: ClientPause
# ------------------------------------------------------------------------------
# Description: Handles pausing the game, clientside
################################################################################

#region ClientPause
ClientPause:
blrl

.set  REG_INPUTS,31
.set  REG_PORT,30

backup

# Get clients inputs
lwz r3, OFST_R13_ODB_ADDR(r13) # data buffer address
lbz REG_PORT, ODB_LOCAL_PLAYER_INDEX(r3)
load  r4,0x804c1fac
mulli r3,REG_PORT,68
add REG_INPUTS,r3,r4

# Check pause state
lbz r3, OFST_R13_ISPAUSE (r13)
cmpwi r3,0
beq ClientPause_Unpaused

ClientPause_Paused:

# Check if holding L R A
lwz r3,0x0(REG_INPUTS)
rlwinm. r0,r3,0,0x40
beq ClientPause_Paused_CheckUnpause
rlwinm. r0,r3,0,0x20
beq ClientPause_Paused_CheckUnpause
rlwinm. r0,r3,0,0x100
beq ClientPause_Paused_CheckUnpause
# Is holding LRA, check for start
rlwinm. r0,r3,0,0x1000
bne ClientPause_Paused_Disconnect

ClientPause_Paused_CheckUnpause:
# Check if just pressed Start
lwz r3,0x8(REG_INPUTS)
rlwinm. r0,r3,0,0x1000
bne ClientPause_Paused_Unpause

# nothing, exit
b ClientPause_Exit

################################################################################
# Disconnect the client
################################################################################

ClientPause_Paused_Disconnect:
# Play SFX
li  r3,2
branchl r12,0x80024030
# End game
branchl r12,0x8016c7f0
# Change scene
li  r3,3
load  r4,0x8046b6a0
stb r3,0x0(r4)
# Unpause clientside
#li  r3,0
#stb r3, OFST_R13_ISPAUSE (r13)
b ClientPause_Exit

################################################################################
# Unpause the client
################################################################################

ClientPause_Paused_Unpause:
# Unpause clientside
li  r3,0
stb r3, OFST_R13_ISPAUSE (r13)
# Show HUD
branchl r12,0x802f33cc
# Show Timer
# Hide Pause UI
mr  r3,REG_PORT
branchl r12,0x801a10fc
b ClientPause_Exit

################################################################################
# Check to pause the client
################################################################################

ClientPause_Unpaused:
# Check if just pressed Start
lwz r3,0x8(REG_INPUTS)
rlwinm. r0,r3,0,0x1000
beq ClientPause_Exit

# Pause clientside
li  r3,1
stb r3, OFST_R13_ISPAUSE (r13)
# Hide HUD
branchl r12,0x802f3394
# Hide Timer
# Show Pause UI
mr  r3,REG_PORT
li  r4,0x5      #shows LRA start and stick
branchl r12,0x801a0fec
# Play SFX
li  r3,5
branchl r12,0x80024030
b ClientPause_Exit

ClientPause_Exit:
li  r3,-1   # always return -1 so the game doesnt actually pause
restore
blr
#endregion


GECKO_EXIT:

restore
