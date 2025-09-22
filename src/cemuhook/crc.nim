func createCrcTable(): array[0 .. 7, array[0 .. 255, uint32]] {.compileTime.} =
  # First, create the basic CRC table (table 0)
  for i in 0.uint32..255.uint32:
    var rem = i
    for j in 0..7:
      if (rem and 1.uint32) > 0'u32:
        rem = (rem shr 1.uint32) xor uint32(0xedb88320)
      else:
        rem = rem shr 1.uint32
    result[0][i] = rem
  
  # Generate the remaining 7 tables for slice-by-8
  for table_idx in 1..7:
    for i in 0..255:
      result[table_idx][i] = (result[table_idx-1][i] shr 8.uint32) xor result[0][result[table_idx-1][i] and 0xff.uint32]

const Crc32Lookup = createCrcTable()

proc calcCrc32*(data: seq[byte]): uint32 =
  result = uint32(0xFFFFFFFF)
  
  for b in data:
    result = (result shr 8) xor Crc32Lookup[0][(result and 0xFF.uint32) xor uint32(b)]

  result = result xor 0xFFFFFFFF'u32

proc calcCrc32*(data: ptr UncheckedArray[byte], len: int): uint32 =
  result = uint32(0xFFFFFFFF)
  
  for idx in 0 .. len-1:
    let b = data[idx]
    result = (result shr 8) xor Crc32Lookup[0][(result and 0xFF.uint32) xor uint32(b)]

  result = result xor 0xFFFFFFFF'u32

# var data : seq[uint8]
# for i in 0 .. 88:
#     data.add(i.uint8)
# echo data.crc32_simple.toHex() # 0x3fc61683
# quit(0)