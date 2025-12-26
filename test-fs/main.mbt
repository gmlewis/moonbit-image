///|
async fn main {
  let tests = [
    ("sample.jpg", "sample.png"),
    ("debug_tex_0_jpeg.jpg", "debug_tex_0_jpeg.png"),
    ("debug_tex_1_jpeg.jpg", "debug_tex_1_jpeg.png"),
    ("debug_tex_2_jpeg.jpg", "debug_tex_2_jpeg.png"),
    ("debug_tex_3_jpeg.jpg", "debug_tex_3_jpeg.png"),
    ("debug_tex_4_jpeg.jpg", "debug_tex_4_jpeg.png"),
  ]

  //
  for tt in tests {
    let jpeg_path = "../test-images/" + tt.0
    let png_path = "../test-images/" + tt.1
    println("Testing \{jpeg_path} against \{png_path}...")

    // Load JPEG
    let jpeg_bytes = @fs.read_file(jpeg_path).binary()
    let jpeg_buf = @gmlewisio.Buffer::from_bytes(jpeg_bytes)
    let (jpeg_img, jpeg_err) = @jpeg.decode(jpeg_buf)
    if jpeg_err != None {
      abort("Error decoding JPEG \{jpeg_path}: \{jpeg_err}")
    }

    // Load PNG
    let png_bytes = @fs.read_file(png_path).binary()
    let png_buf = @gmlewisio.Buffer::from_bytes(png_bytes)
    let (png_img, png_err) = @png.decode(png_buf)
    if png_err != None {
      abort("Error decoding PNG \{png_path}: \{png_err}")
    }

    // Compare
    if not(compare_images(jpeg_img, png_img)) {
      abort("Comparison failed for \{jpeg_path}")
    }
    println("Successfully verified \{jpeg_path}!")
  }
}

///|
fn compare_images(img1 : &@image.Image, img2 : &@image.Image) -> Bool {
  if img1.bounds() != img2.bounds() {
    println("Bounds mismatch: \{img1.bounds()} != \{img2.bounds()}")
    return false
  }
  let bounds = img1.bounds()
  for y = bounds.min.y; y < bounds.max.y; y = y + 1 {
    for x = bounds.min.x; x < bounds.max.x; x = x + 1 {
      let c1 = img1.at(x, y)
      let c2 = img2.at(x, y)
      let (r1, g1, b1, a1) = c1.rgba()
      let (r2, g2, b2, a2) = c2.rgba()
      // Note: We might need a small tolerance here if rounding differs,
      // but let's start with exact match.
      if r1 != r2 || g1 != g2 || b1 != b2 || a1 != a2 {
        println(
          "Pixel mismatch at (\{x}, \{y}): (\{r1}, \{g1}, \{b1}, \{a1}) != (\{r2}, \{g2}, \{b2}, \{a2})",
        )
        return false
      }
    }
  }
  true
}