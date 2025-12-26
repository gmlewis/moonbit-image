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
    let file_path = tt.0
    let bytes = @fs.read_file(file_path).binary()
    let buf = @gmlewisio.Buffer::from_bytes(bytes)
    let (img, err) = @jpeg.decode(buf)
    match err {
      Some(e) => abort("Error decoding JPEG: \{e}")
      None => {
        println("Successfully decoded JPEG!")
        println("Dimensions: \{img.bounds().dx()}x\{img.bounds().dy()}")
      }
    }
  }
}
