///|
async fn main {
  let file_path = "../test-images/sample.jpg"
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
