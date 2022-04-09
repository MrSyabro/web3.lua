#!/usr/bin/env lua
web3 = require "src.web3"
crypto = require "crypto"

seckey = assert(web3.gen_seckey())

client = web3.new("https://rpc-mumbai.matic.today")
client.gasstation_uri = "https://gasstation-mumbai.matic.today/v2"
function client.get_seckey(self)
  return seckey
end
client.address = client:get_addr(seckey)
client.nonce = tonumber (assert(client:eth_getTransactionCount("0x"..web3.tohex(client.address), "latest")))

gas = assert(client:gasstation())

tx = {
  type = 2,
  nonce = client.nonce,
  to = address,
  value = 10^16, --0.01 eth
  data = "message or contract data",
  chainId = 80001,
  gasLimit = 70000,
}
--tx.gasLimit = 21000 + (tx.data and ((#tx.data) * 16)) or 0
tx.maxPriorityFee = math.floor(gas.fast.maxPriorityFee *10^9)
tx.maxFee = math.floor(gas.fast.maxFee *10^9)

print("Address:", web3.tohex(client.address))
function send ()
  print("Out:", client:sendTransaction(tx))
end
