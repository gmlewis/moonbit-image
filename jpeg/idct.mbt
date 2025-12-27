///|
// TODO: const W1 : Int = 2841

///|
// TODO: const W2 : Int = 2676

///|
const W3 : Int = 2408

///|
// TODO: const W5 : Int = 1609

///|
const W6 : Int = 1108

///|
const W7 : Int = 565

///|
const W1PW7 : Int = 3406 // W1 + W7

///|
const W1MW7 : Int = 2276 // W1 - W7

///|
const W2PW6 : Int = 3784 // W2 + W6

///|
const W2MW6 : Int = 1568 // W2 - W6

///|
const W3PW5 : Int = 4017 // W3 + W5

///|
const W3MW5 : Int = 799 // W3 - W5

///|
const R2 : Int = 181 // 256/sqrt(2)

///|
fn idct_block_2pass(src : Array[Int]) -> Array[Int] {
  let b = Array::make(64, 0)
  for i in 0..<64 {
    b[i] = src[i]
  }

  // Horizontal 1-D IDCT.
  for y = 0; y < 8; y = y + 1 {
    let y8 = y * 8
    // If all the AC components are zero, then the IDCT is trivial.
    if b[y8 + 1] == 0 &&
      b[y8 + 2] == 0 &&
      b[y8 + 3] == 0 &&
      b[y8 + 4] == 0 &&
      b[y8 + 5] == 0 &&
      b[y8 + 6] == 0 &&
      b[y8 + 7] == 0 {
      let dc = b[y8 + 0] << 3
      b[y8 + 0] = dc
      b[y8 + 1] = dc
      b[y8 + 2] = dc
      b[y8 + 3] = dc
      b[y8 + 4] = dc
      b[y8 + 5] = dc
      b[y8 + 6] = dc
      b[y8 + 7] = dc
      continue
    }

    // Prescale.
    let mut x0 = (b[y8 + 0] << 11) + 128
    let mut x1 = b[y8 + 4] << 11
    let x2 = b[y8 + 6]
    let x3 = b[y8 + 2]
    let mut x4 = b[y8 + 1]
    let mut x5 = b[y8 + 7]
    let mut x6 = b[y8 + 5]
    let mut x7 = b[y8 + 3]

    // Stage 1.
    let mut x8 = W7 * (x4 + x5)
    x4 = x8 + W1MW7 * x4
    x5 = x8 - W1PW7 * x5
    x8 = W3 * (x6 + x7)
    x6 = x8 - W3MW5 * x6
    x7 = x8 - W3PW5 * x7

    // Stage 2.
    x8 = x0 + x1
    x0 -= x1
    x1 = W6 * (x3 + x2)
    let nx2 = x1 - W2PW6 * x2
    let nx3 = x1 + W2MW6 * x3
    x1 = x4 + x6
    x4 -= x6
    x6 = x5 + x7
    x5 -= x7

    // Stage 3.
    let nx7 = x8 + nx3
    let nx8 = x8 - nx3
    let nx3 = x0 + nx2
    let nx0 = x0 - nx2
    let nx2 = (R2 * (x4 + x5) + 128) >> 8
    let nx4 = (R2 * (x4 - x5) + 128) >> 8

    // Stage 4.
    b[y8 + 0] = (nx7 + x1) >> 8
    b[y8 + 1] = (nx3 + nx2) >> 8
    b[y8 + 2] = (nx0 + nx4) >> 8
    b[y8 + 3] = (nx8 + x6) >> 8
    b[y8 + 4] = (nx8 - x6) >> 8
    b[y8 + 5] = (nx0 - nx4) >> 8
    b[y8 + 6] = (nx3 - nx2) >> 8
    b[y8 + 7] = (nx7 - x1) >> 8
  }

  // Vertical 1-D IDCT.
  for x = 0; x < 8; x = x + 1 {
    // Prescale.
    let mut y0 = (b[x + 8 * 0] << 8) + 8192
    let mut y1 = b[x + 8 * 4] << 8
    let y2 = b[x + 8 * 6]
    let y3 = b[x + 8 * 2]
    let mut y4 = b[x + 8 * 1]
    let mut y5 = b[x + 8 * 7]
    let mut y6 = b[x + 8 * 5]
    let mut y7 = b[x + 8 * 3]

    // Stage 1.
    let mut y8 = W7 * (y4 + y5) + 4
    y4 = (y8 + W1MW7 * y4) >> 3
    y5 = (y8 - W1PW7 * y5) >> 3
    y8 = W3 * (y6 + y7) + 4
    y6 = (y8 - W3MW5 * y6) >> 3
    y7 = (y8 - W3PW5 * y7) >> 3

    // Stage 2.
    y8 = y0 + y1
    y0 -= y1
    y1 = W6 * (y3 + y2) + 4
    let ny2 = (y1 - W2PW6 * y2) >> 3
    let ny3 = (y1 + W2MW6 * y3) >> 3
    y1 = y4 + y6
    y4 -= y6
    y6 = y5 + y7
    y5 -= y7

    // Stage 3.
    let ny7 = y8 + ny3
    let ny8 = y8 - ny3
    let ny3 = y0 + ny2
    let ny0 = y0 - ny2
    let ny2 = (R2 * (y4 + y5) + 128) >> 8
    let ny4 = (R2 * (y4 - y5) + 128) >> 8

    // Stage 4.
    b[x + 8 * 0] = (ny7 + y1) >> 14
    b[x + 8 * 1] = (ny3 + ny2) >> 14
    b[x + 8 * 2] = (ny0 + ny4) >> 14
    b[x + 8 * 3] = (ny8 + y6) >> 14
    b[x + 8 * 4] = (ny8 - y6) >> 14
    b[x + 8 * 5] = (ny0 - ny4) >> 14
    b[x + 8 * 6] = (ny3 - ny2) >> 14
    b[x + 8 * 7] = (ny7 - y1) >> 14
  }
  b
}
