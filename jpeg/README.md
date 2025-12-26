# JPEG Image Decoder

Package `jpeg` implements a JPEG image decoder for MoonBit.

This package supports:
- Baseline (SOF0) Huffman-coded JPEGs.
- 8 bits per component.
- Common chroma subsampling (4:4:4, 4:2:2, 4:2:0, 4:4:0).
- Baseline DCT.
- YCbCr to RGBA conversion.

It does NOT currently support:
- Progressive JPEGs.
- Arithmetic-coded JPEGs.
- Exotic color spaces (CMYK/Adobe).
- Extensive metadata (EXIF parsing).
- Encoding/Writing JPEGs.

## Installation

```sh
moon add gmlewis/image
```

## Usage

```moonbit
fn example(r : &@io.Reader) -> Unit {
  let (img, err) = @jpeg.decode(r)
  match err {
    Some(e) => println("Error: \{e}")
    None => {
      println("Decoded image: \{img.width()}x\{img.height()}")
      // Use img...
    }
  }
}
```

## Implementation Details

This implementation is based on the Go `image/jpeg` implementation.
It uses an integer-based IDCT for performance and portability.

## License

This package is licensed under the Apache-2.0 License.
Based on Go's `image/jpeg` which is governed by a BSD-style license.