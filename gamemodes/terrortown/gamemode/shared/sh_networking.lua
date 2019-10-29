---
-- player based networking
-- TODO message overhead handling (bits reading queue)
-- Issue in this system: there need to be at least 6 network messages to get this system to work (1 per type + unsigned).
-- Additionally every key-value pair needs a string network message and a type based network message.
-- As a result, this will lead with a small amount of data to bad networking performance. Using this with a huge amount of data, this will run in a great performance.
-- The current algorithm focuses to increase the networking performance with the help of calculations (of integer message sizes). This will lower the performance for
-- the server (not the client)

local plymeta = FindMetaTable("Player")
if not plymeta then
	Error("FAILED TO FIND PLAYER TABLE")

	return
end

---
-- Collection for automatic function setup and syncing ordering
-- typ needs to match the result of type()
-- name needs to match the associated net.WriteX function
local syncTypes = {
	{
		typ = "bool",
		name = "Bool"
	},
	{
		typ = "string",
		name = "String"
	},
	{
		typ = "number",
		name = "Number"
	},
	{
		typ = "float",
		name = "Float"
	},
	{
		typ = "Entity",
		name = "Entity"
	},
}

-- init data storage
plymeta.networking = plymeta.networking or InitSNWTable()

local snwTypes = {}

---
-- Creates Getter and Setter function
local function SetupGSFunctions(meta, typ, name)
	snwTypes[typ] = {}

	meta["GetSNW" .. name] = function(key)
		return meta.networking[typ][key]
	end

	meta["SetSNW" .. name] = function(key, val)
		SetSNWData(meta, typ, key, val)
	end
end

---
-- Initializes the networking table with default type tables
local function InitSNWTable()
	return table.Copy(snwTypes)
end

---
--
local function SetSNWData(meta, typ, key, val)
	if meta.networking[typ] == nil or val == meta.networking[typ][key] then return end

	if type(val) ~= typ then
		if typ == "Entity" and not IsValid(val) then -- entity workaround, will avoid Player type
			MsgN("Failed to set SNWData for key '" .. key .. "' (Invalid Entity!)")

			return
		elseif typ ~= "Entity" then
			MsgN("Failed to set SNWData for key '" .. key .. "', value '" .. val .. "' (type mismatch!)")

			return
		end
	end

	hook.Run("TTT2UpdateNetworkingData", meta, key, val)

	meta.networking[typ][key] = val

	if SERVER then
		meta.internalNetworkingCache[typ][key] = val
	end
end

-- Setting up default Getter and Setter functions
for i = 1, #syncTypes do
	local syncTypesEntry = syncTypes[i]

	SetupGSFunctions(plymeta, syncTypesEntry.typ, syncTypesEntry.name)
end

if SERVER then
	---
	-- Calculates the amount of bits of a number
	-- Supports negative numbers and returns as second argument whether its negative of not
	function CalculateBits(val)
		local count = 1
		local uint = true

		if val == 0 then
			return 1, true
		elseif val < 0 then
			if val == -1 then
				return 2, false
			end

			val = math.abs(val) - 1
			uint = false
		end

		while val ~= 0 do
			count = count + 1

			val = bit.rshift(val, 1)
		end

		if uint then
			count = count - 1
		end

		return count, uint
	end

	plymeta.internalNetworkingCache = plymeta.internalNetworkingCache or InitSNWTable()

	util.AddNetworkString("TTT2NetworkingData")

	function plymeta:SyncNetworkingData(ply_or_rf, fullState)
		local tbl = fullState and self.networking or self.internalNetworkingCache

		net.Start("TTT2NetworkingData")

		-- improving number syncing
		local numberBitsTable = {}
		local countUnsigned = 0
		local countSigned = 0

		-- create a list index by bits amount
		for k, v in pairs(tbl.number) do
			local bits, unsigned = CalculateBits(v)
			if bits == 0 or bits > 32 then continue end -- exclude data that can not be synced

			local index = unsigned and 1 or 2

			numberBitsTable[index] = numberBitsTable[index] or {}
			numberBitsTable[index][bits] = numberBitsTable[index][bits] or {}
			numberBitsTable[index][bits][#numberBitsTable[index][bits] + 1] = {
				key = k,
				val = v,
			}

			if unsigned then
				countUnsigned = countUnsigned + 1
			else
				countSigned = countUnsigned + 1
			end
		end

		for tableIndex = 1, 2 do
			local writeFnc = tableIndex == 1 and net.WriteUInt or net.WriteInt

			net.WriteUInt(tableIndex == 1 and countUnsigned or countSigned, 16) -- amount of following network messages of this type

			-- at first sync unsigned numbers
			for bits, tmp in pairs(numberBitsTable[tableIndex]) do
				net.WriteUInt(#tmp, 16) -- amount of messages of this bit set
				net.WriteUInt(bits - 1, 4) -- current bits amount

				for k = 1, #tmp do
					local tmpK = tmp[k]

					net.WriteString(tmpK.key) -- write data key
					writeFnc(tmpK.val, bits) -- write data value
				end
			end
		end

		for i = 1, #syncTypes do
			local entry = syncTypes[i]

			if entry.typ == "number" then continue end

			net.WriteUInt(table.Count(tbl[entry.typ]), 16) -- amount of following network messages of this type

			for k, v in pairs(tbl[entry.typ]) do
				net.WriteString(k)
				net["Write" .. entry.name](k)
			end
		end

		net.Send(ply_or_rf)
	end
else
	local function TTT2NetworkingData()
		-- TODO
	end
	net.Receive("TTT2NetworkingData", TTT2NetworkingData)
end

function plymeta:ResetNetworkingData()
	hook.Run("TTT2ResetNetworkingData", self)

	self.networking = {
		bodyFound = false,
		firstFound = -1,
		lastFound = -1,
		roleFound = false,
	}
end
