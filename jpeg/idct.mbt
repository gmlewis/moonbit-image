///|
let idct_matrix : Array[Int] = [
  11585, 11585, 11585, 11585, 11585, 11585, 11585, 11585,
  16069, 13623, 9102, 3196, -3196, -9102, -13623, -16069,
  15137, 6270, -6270, -15137, -15137, -6270, 6270, 15137,
  13623, -3196, -16069, -9102, 9102, 16069, 3196, -13623,
  11585, -11585, -11585, 11585, 11585, -11585, -11585, 11585,
  9102, -16069, 3196, 13623, -13623, -3196, 16069, -9102,
  6270, -15137, 15137, -6270, -6270, 15137, -15137, 6270,
  3196, -9102, 13623, -16069, 16069, -13623, 9102, -3196,
]

///|
fn idct_block_2pass(blk : Array[Int]) -> Array[Int] {
  let out = Array::make(64, 0)
  let tmp = Array::make(64, 0)
  // Pass 1: rows
  for y in 0..<8 {
    for x in 0..<8 {
      let mut s = 0L
      for u in 0..<8 {
        let cu = idct_matrix[u * 8 + x].to_int64()
        let coeff = blk[y * 8 + u].to_int64()
        s = s + cu * coeff
      }
      tmp[y * 8 + x] = ((s + (1L << 10)) >> 11).to_int()
    }
  }
  // Pass 2: columns
  for x in 0..<8 {
    for y in 0..<8 {
      let mut s = 0L
      for v in 0..<8 {
        let cv = idct_matrix[v * 8 + y].to_int64()
        let coeff = tmp[v * 8 + x].to_int64()
        s = s + cv * coeff
      }
      out[y * 8 + x] = ((s + (1L << 18)) >> 19).to_int()
    }
  }
  out
}