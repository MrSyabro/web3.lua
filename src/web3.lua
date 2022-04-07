local json = require ("dkjson")
local https = require ("ssl.https")
local crypto = require ("crypto")

local M = {}

local function tohex(str)
	if type(str) == "string" then
		return (str:gsub('.', function (c)
			return string.format('%02x', string.byte(c))
		end))
	elseif type(str) == "number" then
		return string.format("%x", str)
	end
end
local function fromhex(str)
	return (str:gsub('..', function (cc)
		return string.char(tonumber(cc, 16))
	end))
end
local function tobytes(num)
  local out = ""
  while num > 0xff do
    out = string.char(num & 0xff)..out
    num = num >> 8
  end
  if num > 0 then out = string.char(num)..out end
  return out
end
M.tohex = tohex
M.fromhex = fromhex
M.tobytes = tobytes

local function rpc_request(url, func, id, data)
	local request = {
		jsonrpc = "2.0",
		method = func,
		id = id,
		params = data,
	}
	local request_json = json.encode(request)
	local response_json, err = https.request (url, request_json)
	if not response_json then return nil, err end

	local response = json.decode(response_json)

	if response.error then return nil, response.error.message end

	return response.result
end

local function expand(str)
	local s = 64 - string.len(str)
	str = string.rep("0", s)..str

	return str
end

local function data_pack(inputs, ...)
  if not inputs or #inputs < 1 then return nil end
	local args = {...}
	local empty = #inputs + 1
	local out = {}
	for k, i in ipairs(inputs) do
		local str
		if i == "address"
		or i == "uint32"
		or i == "bytes32"
		or i == "uint256"
		or i == "int256"
		or i == "bool"
		then
			if i == "address" then
				str = expand(args[k])
			elseif i == "bool" then
				str = expand(args[k] and "1" or "0")
			else
				str = expand(tohex(args[k]))
			end
		elseif i == "string" then
			str = expand(string.format("%X", (empty -1) * 0x20))
			out[empty] = expand(string.format("%X", string.len(args[k])))
			local arg = tohex(args[k])
			while string.len(arg) > 64 do
				empty = empty + 1
				local str = arg:sub(1, 64)
				if string.len(arg) > 64 then arg = arg:sub(65, -1) end
				out[empty] = str
			end
			local s = 64 - string.len(arg)
			arg = arg..string.rep("0", s)
			out[empty+1] = arg
			empty = empty + 2
		elseif i == "address[]" then
			str = expand(string.format("%X", (empty -1) * 0x20))
			out[empty] = expand(string.format("%X", #args[k]))
			empty = empty + 1
			for _, addr in ipairs(args[k]) do
				out[empty] = expand(addr)
				empty = empty + 1
			end
		end

		out[k] = str
	end

	return table.concat(out)
end
M.data_pack = data_pack

local function data_unpack(outputs, data)
  if not outputs or #outputs < 1 then return nil end
	local out = {}

	for k, i in ipairs(outputs) do
		if i == "address"
		or i == "uint32"
		or i == "bytes32"
		or i == "uint256"
		or i == "int256"
		or i == "bool"
		then
			if i == "address" then
				table.insert(out, data:sub((k-1)*64+25, (k)*64))
			elseif i == "bool" then
				table.insert(out, data:sub((k-1)*64+63, (k)*64) == "1")
			else
				table.insert(out, tonumber(data:sub((k-1)*64+48, k*64), 16))
			end
		elseif i == "string" then
			local offset = tonumber(data:sub((k-1)*64+61, k*64), 16) * 2
			local size = tonumber(data:sub(offset + 61, offset + 64), 16) * 2
			local hex = data:sub(offset + 0x41, offset + 0x40 + size)
			local str = fromhex(hex)
			table.insert(out, str)
		elseif i == "address[]" then
			local address = {}
			local offset = tonumber(data:sub((k-1)*64+61, k * 64), 16) * 2
			local n = tonumber(data:sub(offset + 61, offset + 64), 16)
			for i = 1, n do
				address[i] = data:sub(offset + i * 0x40 + 25, offset + (i+1) * 0x40)
			end
			table.insert(out, address)
		end
	end
	return table.unpack(out)
end
M.data_unpack = data_unpack

local function mt_index (self, key)
	local method = key
	return function (self, ...)
		local args = {...}

		return rpc_request(self.url, method, self.id, args)
	end
end

local function checkArg(args, check)
	if #args ~= check then return false end
	return true
end

local function contractABI(self, abi, address)
	if type(abi) == "string" then
		abi = json.decode(abi)
	end
	local client = self
	local contract = {}
	contract.address = address
	contract.gas = 3000000

	for k, i in ipairs(abi) do
		if i.name then
			local abi = i
      local inputs_to_pack, outs_to_unpack

			if type(abi.outputs) == "table" and #abi.outputs > 0 then
				outs_to_unpack = {}
				for ik, out in ipairs(abi.outputs) do
					outs_to_unpack[ik] = out.type
				end
			end

      if abi.type == "function" then
      if abi.stateMutability == "nonpayable" then
        local method = {abi.name}

        if #abi.inputs > 0 then
  				inputs_to_pack = {}
  				for ik, input in ipairs(abi.inputs) do
  					inputs_to_pack[ik] = input.type
  				end
  				method[2] = "("
  				method[3] = table.concat(inputs_to_pack, ",")
  				method[4] = ")"
  			else
  				method[2] = "()"
        end
			
			  method = table.concat(method)
			  local method_hash = crypto.sha3(method):sub(1, 5)
			  
			  contract[abi.name] = function (self, ...)
			    local args = {...}
			    local in_packed_data = data_pack(inputs_to_pack, args)
			    local params = {
						to = self.address,
						from = "0x"..tohex(client.address),
						data = "0x"..tohex(method_hash) .. (in_packed_data or ""),
					}
					
					if client.nonce then params.nonce = client.nonce + 1 end
					
					local params_hash = crypto.keccak256(json.encode(params))
					local signature = crypto.sign(fromhex(client:get_seckey()), params_hash)
					signature = tohex(signature)
					params.R = signature:sub(1, 32)
					params.S = signature:sub(33, -1)
					--params.V = fromhex(signature:sub(63, 64)) +24
					
					out_packed_data, err = client:eth_sendRawTransaction("0x"..tohex(json.encode(params)))
			    if err then return nil, err end

          if #outs_to_unpack > 0 then
  				 out_data = data_unpack (outs_to_unpack, out_packed_data:sub(3, -1))
  				 return out_data
  				else
  					return nil
  				end
			  end
			elseif abi.stateMutability == "view" then
        local method = abi.name.."()"
				local method_hash = "0x"..tohex(crypto.sha3(method)):sub(1, 10)

        contract[abi.name] = function(self)
          local params = {
  					to = self.address,
  					data = method_hash
  				}
  				out_packed_data, err = client:eth_call(params, "latest")
          if err then return nil, err end
          
          if #outs_to_unpack > 0 then
    				local out_data = data_unpack (outs_to_unpack, out_packed_data:sub(3, -1))
    				return out_data
  				else
  					return nil
  				end
        end
        end
      end
		end
	end

	return contract
end

local function signTransaction(self, transaction)
  if not self.get_seckey then return end
  local seckey = self:get_seckey()
  if #seckey > 32 then 
    seckey = fromhex(seckey) -- convert to bytes array
  end

  local urtl_raw, err = crypto.serializeTx (transaction)
  if not urtl_raw then return nil, err end
  local sign, recid = crypto.sign(seckey, crypto.sha3(urtl_raw))
  
  transaction[7] = tobytes(recid + transaction.chainId*2 + 35)
  transaction[8] = sign:sub(1, 32)
  transaction[9] = sign:sub(33, 64)
  
  local rtl_raw = crypto.serializeTx(transaction)
  
  return rtl_raw
end

local function sendTransaction (self, tx)
  if not tx.to
  or not tx.value
  then return nil, "bad argumet" end

  if type(tx.nonce) == "number" then tx[1] = tobytes(tx.nonce)
  else tx[1] = tx.nonce end
  if type(tx.gasPrice) == "number" then tx[2] = tobytes(tx.gasPrice)
  else tx[2] = tx.gasPrice end
  if type(tx.gasLimit) == "number" then tx[3] = tobytes(tx.gasLimit)
  else tx[3] = tx.gasLimit end
  if type(tx.value) == "number" then tx[5] = tobytes(tx.value)
  else tx[5] = tx.value end
  if type(tx.chainId == "number") then tx[7] = tobytes(tx.chainId)
  else tx[7] = tx.chainId end
  tx[6] = tx.data
  tx[4] = tx.to
  tx[8] = ""
  tx[9] = ""

  local rtl_raw, err = signTransaction(self, tx)
  if err then print(err) end
  if not rtl_raw then return nil, "not signed" end
  
  --return rtl_raw
  return self:eth_sendRawTransaction("0x"..tohex(rtl_raw))
end

local function get_addr(self, seckey)
  if not seckey or not self.get_seckey then return end
  --if self.address then return self.address end
  local pubkey = crypto.sec_to_pub(seckey or self:get_seckey()):sub (2, -1)
  return crypto.sha3(pubkey):sub(-20, -1)
end

local mt = {__index = mt_index}

function M.new(url, address)
	local api = {
		url = url,
		address = address,
		id = math.random(1, 50),
		contractABI = contractABI,
		web3_sha3 = crypto.sha3,
		signTransaction = signTransaction,
		sendTransaction = sendTransaction,
		get_addr = get_addr,
	}

	return setmetatable(api, mt)
end

return M
