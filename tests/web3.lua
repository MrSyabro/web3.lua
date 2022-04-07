web3 = require "src.web3"
crypto = require "crypto"
--s = require "serialize"

seckey = web3.fromhex ""

client = web3.new("https://rpc-mumbai.matic.today")
address = web3.fromhex "789C8e1616D75a9F4c3560f779Df13b707cC7ac3"
function client.get_seckey(self)
  return seckey
end
client.address = client:get_addr(seckey)
client.nonce = client:eth_getTransactionCount("0x"..web3.tohex(client.address), "latest")

tx = {
  nonce = string.char(client.nonce),
  gasPrice = web3.tobytes(3*10^9),
  gasLimit = web3.tobytes(21000),
  to = address,
  value = web3.tobytes(10^16),
  data = "",
  chainId = 80001,
}

print("Address:", web3.tohex(client.address))
print("Out:", client:sendTransaction(tx))