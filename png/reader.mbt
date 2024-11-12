/// Package png implements a PNG image decoder and encoder.
///
/// The PNG specification is at https://www.w3.org/TR/PNG/.
///
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/png/reader.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

// import (
// 	"compress/zlib"
// 	"encoding/binary"
// 	"fmt"
// 	"hash"
// 	"hash/crc32"
// 	"image"
// 	"image/color"
// 	"io"
// )

// Color type, as per the PNG spec.
const CT_GRAYSCALE = 0

const CT_TRUE_COLOR = 2

const CT_PALETTED = 3

const CT_GRAYSCALE_ALPHA = 4

const CT_TRUE_COLOR_ALPHA = 6

// A cb is a combination of color type and bit depth.
const CB_INVALID = 0

const CB_G1 = 1

const CB_G2 = 2

const CB_G4 = 3

const CB_G8 = 4

const CB_GA8 = 5

const CB_TC8 = 6

const CB_P1 = 7

const CB_P2 = 8

const CB_P4 = 9

const CB_P8 = 10

const CB_TCA8 = 11

const CB_G16 = 12

const CB_GA16 = 13

const CB_TC16 = 14

const CB_TCA16 = 15

fn cb_paletted(cb : Int) -> Bool {
  CB_P1 <= cb && cb <= CB_P8
}

fn cb_true_color(cb : Int) -> Bool {
  cb == CB_TC8 || cb == CB_TC16
}

// Filter type, as per the PNG spec.
const FT_NONE = 0

const FT_SUB = 1

const FT_UP = 2

const FT_AVERAGE = 3

const FT_PAETH = 4

const N_FILTER = 5

// Interlace type.
const IT_NONE = 0

const IT_ADAM7 = 1

// InterlaceScan defines the placement and size of a pass for Adam7 interlacing.
struct InterlaceScan {
  x_factor : Int
  y_factor : Int
  x_offset : Int
  y_offset : Int
}

// interlacing defines Adam7 interlacing, with 7 passes of reduced images.
// See https://www.w3.org/TR/PNG/#8Interlace
let interlacing : Array[InterlaceScan] = [
  { x_factor: 8, y_factor: 8, x_offset: 0, y_offset: 0 },
  { x_factor: 8, y_factor: 8, x_offset: 4, y_offset: 0 },
  { x_factor: 4, y_factor: 8, x_offset: 0, y_offset: 4 },
  { x_factor: 4, y_factor: 4, x_offset: 2, y_offset: 0 },
  { x_factor: 2, y_factor: 4, x_offset: 0, y_offset: 2 },
  { x_factor: 2, y_factor: 2, x_offset: 1, y_offset: 0 },
  { x_factor: 1, y_factor: 2, x_offset: 0, y_offset: 1 },
]

// Decoding stage.
// The PNG specification says that the IHDR, PLTE (if present), tRNS (if
// present), IDAT and IEND chunks must appear in that order. There may be
// multiple IDAT chunks, and IDAT chunks must be sequential (i.e. they may not
// have any other chunks between them).
// https://www.w3.org/TR/PNG/#5ChunkOrdering
const DS_START = 0

const DS_SEEN_IHDR = 1

const DS_SEEN_PLTE = 2

const DS_SEENT_RNS = 3

const DS_SEEN_IDAT = 4

const DS_SEEN_IEND = 5

const PNG_HEADER = b"\x89PNG\r\n\x1a\n"

struct Decoder {
  r : @io.Reader
  img : @image.Image
  crc : @hash.Hash32
  width : Int
  height : Int
  depth : Int
  palette : @color.Palette
  cb : Int
  stage : Int
  idat_length : UInt
  tmp : Slice[Byte] // [3 * 256]byte
  interlace : Int

  // use_transparent and transparent are used for grayscale and truecolor
  // transparency, as opposed to palette transparency.
  use_transparent : Bool
  transparent : Slice[Byte] // [6]byte
}

// A FormatError reports that the input is not a valid PNG.
type! FormatError String derive(Show, Eq)

fn format_error(e : String) -> FormatError {
  FormatError("png: invalid format: \{e}")
}

pub let chunk_order_error : FormatError = format_error("chunk out of order")

// An UnsupportedError reports that the input uses a valid but unimplemented PNG feature.
type! UnsupportedError String derive(Show, Eq)

fn unsupported_error(e : String) -> UnsupportedError {
  UnsupportedError("png: unsupported feature: \{e}")
}

// func (d *decoder) parseIHDR(length uint32) error {
// 	if length != 13 {
// 		return format_error("bad IHDR length")
// 	}
// 	if _, err := io.ReadFull(d.r, d.tmp[:13]); err != nil {
// 		return err
// 	}
// 	d.crc.Write(d.tmp[:13])
// 	if d.tmp[10] != 0 {
// 		return unsupported_error("compression method")
// 	}
// 	if d.tmp[11] != 0 {
// 		return unsupported_error("filter method")
// 	}
// 	if d.tmp[12] != IT_NONE && d.tmp[12] != IT_ADAM7 {
// 		return format_error("invalid interlace method")
// 	}
// 	d.interlace = int(d.tmp[12])

// 	w := int32(binary.BigEndian.Uint32(d.tmp[0:4]))
// 	h := int32(binary.BigEndian.Uint32(d.tmp[4:8]))
// 	if w <= 0 || h <= 0 {
// 		return format_error("non-positive dimension")
// 	}
// 	nPixels64 := int64(w) * int64(h)
// 	nPixels := int(nPixels64)
// 	if nPixels64 != int64(nPixels) {
// 		return unsupported_error("dimension overflow")
// 	}
// 	// There can be up to 8 bytes per pixel, for 16 bits per channel RGBA.
// 	if nPixels != (nPixels*8)/8 {
// 		return unsupported_error("dimension overflow")
// 	}

// 	d.cb = cbInvalid
// 	d.depth = int(d.tmp[8])
// 	switch d.depth {
// 	case 1:
// 		switch d.tmp[9] {
// 		case CT_GRAYSCALE:
// 			d.cb = cbG1
// 		case CT_PALETTED:
// 			d.cb = CB_P1
// 		}
// 	case 2:
// 		switch d.tmp[9] {
// 		case CT_GRAYSCALE:
// 			d.cb = cbG2
// 		case CT_PALETTED:
// 			d.cb = cb_p2
// 		}
// 	case 4:
// 		switch d.tmp[9] {
// 		case CT_GRAYSCALE:
// 			d.cb = cbG4
// 		case CT_PALETTED:
// 			d.cb = cb_p4
// 		}
// 	case 8:
// 		switch d.tmp[9] {
// 		case CT_GRAYSCALE:
// 			d.cb = cbG8
// 		case CT_TRUE_COLOR:
// 			d.cb = CB_TC8
// 		case CT_PALETTED:
// 			d.cb = CB_P8
// 		case CT_GRAYSCALE_ALPHA:
// 			d.cb = cbGA8
// 		case CT_TRUE_COLOR_ALPHA:
// 			d.cb = CB_TCA8
// 		}
// 	case 16:
// 		switch d.tmp[9] {
// 		case CT_GRAYSCALE:
// 			d.cb = cbG16
// 		case CT_TRUE_COLOR:
// 			d.cb = CB_TC16
// 		case CT_GRAYSCALE_ALPHA:
// 			d.cb = cbGA16
// 		case CT_TRUE_COLOR_ALPHA:
// 			d.cb = CB_TCA16
// 		}
// 	}
// 	if d.cb == cbInvalid {
// 		return unsupported_error(fmt.Sprintf("bit depth %d, color type %d", d.tmp[8], d.tmp[9]))
// 	}
// 	d.width, d.height = int(w), int(h)
// 	return d.verifyChecksum()
// }

// func (d *decoder) parsePLTE(length uint32) error {
// 	np := int(length / 3) // The number of palette entries.
// 	if length%3 != 0 || np <= 0 || np > 256 || np > 1<<uint(d.depth) {
// 		return format_error("bad PLTE length")
// 	}
// 	n, err := io.ReadFull(d.r, d.tmp[:3*np])
// 	if err != nil {
// 		return err
// 	}
// 	d.crc.Write(d.tmp[:n])
// 	switch d.cb {
// 	case CB_P1, cb_p2, cb_p4, CB_P8:
// 		d.palette = make(color.Palette, 256)
// 		for i := 0; i < np; i++ {
// 			d.palette[i] = color.RGBA{d.tmp[3*i+0], d.tmp[3*i+1], d.tmp[3*i+2], 0xff}
// 		}
// 		for i := np; i < 256; i++ {
// 			// Initialize the rest of the palette to opaque black. The spec (section
// 			// 11.2.3) says that "any out-of-range pixel value found in the image data
// 			// is an error", but some real-world PNG files have out-of-range pixel
// 			// values. We fall back to opaque black, the same as libpng 1.5.13;
// 			// ImageMagick 6.5.7 returns an error.
// 			d.palette[i] = color.RGBA{0x00, 0x00, 0x00, 0xff}
// 		}
// 		d.palette = d.palette[:np]
// 	case CB_TC8, CB_TCA8, CB_TC16, CB_TCA16:
// 		// As per the PNG spec, a PLTE chunk is optional (and for practical purposes,
// 		// ignorable) for the CT_TRUE_COLOR and CT_TRUE_COLOR_ALPHA color types (section 4.1.2).
// 	default:
// 		return format_error("PLTE, color type mismatch")
// 	}
// 	return d.verifyChecksum()
// }

// func (d *decoder) parsetRNS(length uint32) error {
// 	switch d.cb {
// 	case cbG1, cbG2, cbG4, cbG8, cbG16:
// 		if length != 2 {
// 			return format_error("bad tRNS length")
// 		}
// 		n, err := io.ReadFull(d.r, d.tmp[:length])
// 		if err != nil {
// 			return err
// 		}
// 		d.crc.Write(d.tmp[:n])

// 		copy(d.transparent[:], d.tmp[:length])
// 		switch d.cb {
// 		case cbG1:
// 			d.transparent[1] *= 0xff
// 		case cbG2:
// 			d.transparent[1] *= 0x55
// 		case cbG4:
// 			d.transparent[1] *= 0x11
// 		}
// 		d.use_transparent = true

// 	case CB_TC8, CB_TC16:
// 		if length != 6 {
// 			return format_error("bad tRNS length")
// 		}
// 		n, err := io.ReadFull(d.r, d.tmp[:length])
// 		if err != nil {
// 			return err
// 		}
// 		d.crc.Write(d.tmp[:n])

// 		copy(d.transparent[:], d.tmp[:length])
// 		d.use_transparent = true

// 	case CB_P1, cb_p2, cb_p4, CB_P8:
// 		if length > 256 {
// 			return format_error("bad tRNS length")
// 		}
// 		n, err := io.ReadFull(d.r, d.tmp[:length])
// 		if err != nil {
// 			return err
// 		}
// 		d.crc.Write(d.tmp[:n])

// 		if len(d.palette) < n {
// 			d.palette = d.palette[:n]
// 		}
// 		for i := 0; i < n; i++ {
// 			rgba := d.palette[i].(color.RGBA)
// 			d.palette[i] = color.NRGBA{rgba.R, rgba.G, rgba.B, d.tmp[i]}
// 		}

// 	default:
// 		return format_error("tRNS, color type mismatch")
// 	}
// 	return d.verifyChecksum()
// }

// // Read presents one or more IDAT chunks as one continuous stream (minus the
// // intermediate chunk headers and footers). If the PNG data looked like:
// //
// //	... len0 IDAT xxx crc0 len1 IDAT yy crc1 len2 IEND crc2
// //
// // then this reader presents xxxyy. For well-formed PNG data, the decoder state
// // immediately before the first Read call is that d.r is positioned between the
// // first IDAT and xxx, and the decoder state immediately after the last Read
// // call is that d.r is positioned between yy and crc1.
// func (d *decoder) Read(p []byte) (int, error) {
// 	if len(p) == 0 {
// 		return 0, nil
// 	}
// 	for d.idat_length == 0 {
// 		// We have exhausted an IDAT chunk. Verify the checksum of that chunk.
// 		if err := d.verifyChecksum(); err != nil {
// 			return 0, err
// 		}
// 		// Read the length and chunk type of the next chunk, and check that
// 		// it is an IDAT chunk.
// 		if _, err := io.ReadFull(d.r, d.tmp[:8]); err != nil {
// 			return 0, err
// 		}
// 		d.idat_length = binary.BigEndian.Uint32(d.tmp[:4])
// 		if string(d.tmp[4:8]) != "IDAT" {
// 			return 0, format_error("not enough pixel data")
// 		}
// 		d.crc.Reset()
// 		d.crc.Write(d.tmp[4:8])
// 	}
// 	if int(d.idat_length) < 0 {
// 		return 0, unsupported_error("IDAT chunk length overflow")
// 	}
// 	n, err := d.r.Read(p[:min(len(p), int(d.idat_length))])
// 	d.crc.Write(p[:n])
// 	d.idat_length -= uint32(n)
// 	return n, err
// }

// // decode decodes the IDAT data into an image.
// func (d *decoder) decode() (image.Image, error) {
// 	r, err := zlib.NewReader(d)
// 	if err != nil {
// 		return nil, err
// 	}
// 	defer r.Close()
// 	var img image.Image
// 	if d.interlace == IT_NONE {
// 		img, err = d.readImagePass(r, 0, false)
// 		if err != nil {
// 			return nil, err
// 		}
// 	} else if d.interlace == IT_ADAM7 {
// 		// Allocate a blank image of the full size.
// 		img, err = d.readImagePass(nil, 0, true)
// 		if err != nil {
// 			return nil, err
// 		}
// 		for pass := 0; pass < 7; pass++ {
// 			imagePass, err := d.readImagePass(r, pass, false)
// 			if err != nil {
// 				return nil, err
// 			}
// 			if imagePass != nil {
// 				d.mergePassInto(img, imagePass, pass)
// 			}
// 		}
// 	}

// 	// Check for EOF, to verify the zlib checksum.
// 	n := 0
// 	for i := 0; n == 0 && err == nil; i++ {
// 		if i == 100 {
// 			return nil, io.ErrNoProgress
// 		}
// 		n, err = r.Read(d.tmp[:1])
// 	}
// 	if err != nil && err != io.EOF {
// 		return nil, format_error(err.Error())
// 	}
// 	if n != 0 || d.idat_length != 0 {
// 		return nil, format_error("too much pixel data")
// 	}

// 	return img, nil
// }

// // readImagePass reads a single image pass, sized according to the pass number.
// func (d *decoder) readImagePass(r io.Reader, pass int, allocateOnly bool) (image.Image, error) {
// 	bitsPerPixel := 0
// 	pix_offset := 0
// 	var (
// 		gray     *image.Gray
// 		rgba     *image.RGBA
// 		paletted *image.Paletted
// 		nrgba    *image.NRGBA
// 		gray16   *image.Gray16
// 		rgba64   *image.RGBA64
// 		nrgba64  *image.NRGBA64
// 		img      image.Image
// 	)
// 	width, height := d.width, d.height
// 	if d.interlace == IT_ADAM7 && !allocateOnly {
// 		p := interlacing[pass]
// 		// Add the multiplication factor and subtract one, effectively rounding up.
// 		width = (width - p.x_offset + p.x_factor - 1) / p.x_factor
// 		height = (height - p.y_offset + p.y_factor - 1) / p.y_factor
// 		// A PNG image can't have zero width or height, but for an interlaced
// 		// image, an individual pass might have zero width or height. If so, we
// 		// shouldn't even read a per-row filter type byte, so return early.
// 		if width == 0 || height == 0 {
// 			return nil, nil
// 		}
// 	}
// 	switch d.cb {
// 	case cbG1, cbG2, cbG4, cbG8:
// 		bitsPerPixel = d.depth
// 		if d.use_transparent {
// 			nrgba = image.NewNRGBA(image.Rect(0, 0, width, height))
// 			img = nrgba
// 		} else {
// 			gray = image.NewGray(image.Rect(0, 0, width, height))
// 			img = gray
// 		}
// 	case cbGA8:
// 		bitsPerPixel = 16
// 		nrgba = image.NewNRGBA(image.Rect(0, 0, width, height))
// 		img = nrgba
// 	case CB_TC8:
// 		bitsPerPixel = 24
// 		if d.use_transparent {
// 			nrgba = image.NewNRGBA(image.Rect(0, 0, width, height))
// 			img = nrgba
// 		} else {
// 			rgba = image.NewRGBA(image.Rect(0, 0, width, height))
// 			img = rgba
// 		}
// 	case CB_P1, cb_p2, cb_p4, CB_P8:
// 		bitsPerPixel = d.depth
// 		paletted = image.NewPaletted(image.Rect(0, 0, width, height), d.palette)
// 		img = paletted
// 	case CB_TCA8:
// 		bitsPerPixel = 32
// 		nrgba = image.NewNRGBA(image.Rect(0, 0, width, height))
// 		img = nrgba
// 	case cbG16:
// 		bitsPerPixel = 16
// 		if d.use_transparent {
// 			nrgba64 = image.NewNRGBA64(image.Rect(0, 0, width, height))
// 			img = nrgba64
// 		} else {
// 			gray16 = image.NewGray16(image.Rect(0, 0, width, height))
// 			img = gray16
// 		}
// 	case cbGA16:
// 		bitsPerPixel = 32
// 		nrgba64 = image.NewNRGBA64(image.Rect(0, 0, width, height))
// 		img = nrgba64
// 	case CB_TC16:
// 		bitsPerPixel = 48
// 		if d.use_transparent {
// 			nrgba64 = image.NewNRGBA64(image.Rect(0, 0, width, height))
// 			img = nrgba64
// 		} else {
// 			rgba64 = image.NewRGBA64(image.Rect(0, 0, width, height))
// 			img = rgba64
// 		}
// 	case CB_TCA16:
// 		bitsPerPixel = 64
// 		nrgba64 = image.NewNRGBA64(image.Rect(0, 0, width, height))
// 		img = nrgba64
// 	}
// 	if allocateOnly {
// 		return img, nil
// 	}
// 	bytesPerPixel := (bitsPerPixel + 7) / 8

// 	// The +1 is for the per-row filter type, which is at cr[0].
// 	rowSize := 1 + (int64(bitsPerPixel)*int64(width)+7)/8
// 	if rowSize != int64(int(rowSize)) {
// 		return nil, unsupported_error("dimension overflow")
// 	}
// 	// cr and pr are the bytes for the current and previous row.
// 	cr := make([]uint8, rowSize)
// 	pr := make([]uint8, rowSize)

// 	for y := 0; y < height; y++ {
// 		// Read the decompressed bytes.
// 		_, err := io.ReadFull(r, cr)
// 		if err != nil {
// 			if err == io.EOF || err == io.ErrUnexpectedEOF {
// 				return nil, format_error("not enough pixel data")
// 			}
// 			return nil, err
// 		}

// 		// Apply the filter.
// 		cdat := cr[1:]
// 		pdat := pr[1:]
// 		switch cr[0] {
// 		case FT_NONE:
// 			// No-op.
// 		case FT_SUB:
// 			for i := bytesPerPixel; i < len(cdat); i++ {
// 				cdat[i] += cdat[i-bytesPerPixel]
// 			}
// 		case FT_UP:
// 			for i, p := range pdat {
// 				cdat[i] += p
// 			}
// 		case FT_AVERAGE:
// 			// The first column has no column to the left of it, so it is a
// 			// special case. We know that the first column exists because we
// 			// check above that width != 0, and so len(cdat) != 0.
// 			for i := 0; i < bytesPerPixel; i++ {
// 				cdat[i] += pdat[i] / 2
// 			}
// 			for i := bytesPerPixel; i < len(cdat); i++ {
// 				cdat[i] += uint8((int(cdat[i-bytesPerPixel]) + int(pdat[i])) / 2)
// 			}
// 		case FT_PAETH:
// 			filterPaeth(cdat, pdat, bytesPerPixel)
// 		default:
// 			return nil, format_error("bad filter type")
// 		}

// 		// Convert from bytes to colors.
// 		switch d.cb {
// 		case cbG1:
// 			if d.use_transparent {
// 				ty := d.transparent[1]
// 				for x := 0; x < width; x += 8 {
// 					b := cdat[x/8]
// 					for x2 := 0; x2 < 8 && x+x2 < width; x2++ {
// 						ycol := (b >> 7) * 0xff
// 						acol := uint8(0xff)
// 						if ycol == ty {
// 							acol = 0x00
// 						}
// 						nrgba.SetNRGBA(x+x2, y, color.NRGBA{ycol, ycol, ycol, acol})
// 						b <<= 1
// 					}
// 				}
// 			} else {
// 				for x := 0; x < width; x += 8 {
// 					b := cdat[x/8]
// 					for x2 := 0; x2 < 8 && x+x2 < width; x2++ {
// 						gray.SetGray(x+x2, y, color.Gray{(b >> 7) * 0xff})
// 						b <<= 1
// 					}
// 				}
// 			}
// 		case cbG2:
// 			if d.use_transparent {
// 				ty := d.transparent[1]
// 				for x := 0; x < width; x += 4 {
// 					b := cdat[x/4]
// 					for x2 := 0; x2 < 4 && x+x2 < width; x2++ {
// 						ycol := (b >> 6) * 0x55
// 						acol := uint8(0xff)
// 						if ycol == ty {
// 							acol = 0x00
// 						}
// 						nrgba.SetNRGBA(x+x2, y, color.NRGBA{ycol, ycol, ycol, acol})
// 						b <<= 2
// 					}
// 				}
// 			} else {
// 				for x := 0; x < width; x += 4 {
// 					b := cdat[x/4]
// 					for x2 := 0; x2 < 4 && x+x2 < width; x2++ {
// 						gray.SetGray(x+x2, y, color.Gray{(b >> 6) * 0x55})
// 						b <<= 2
// 					}
// 				}
// 			}
// 		case cbG4:
// 			if d.use_transparent {
// 				ty := d.transparent[1]
// 				for x := 0; x < width; x += 2 {
// 					b := cdat[x/2]
// 					for x2 := 0; x2 < 2 && x+x2 < width; x2++ {
// 						ycol := (b >> 4) * 0x11
// 						acol := uint8(0xff)
// 						if ycol == ty {
// 							acol = 0x00
// 						}
// 						nrgba.SetNRGBA(x+x2, y, color.NRGBA{ycol, ycol, ycol, acol})
// 						b <<= 4
// 					}
// 				}
// 			} else {
// 				for x := 0; x < width; x += 2 {
// 					b := cdat[x/2]
// 					for x2 := 0; x2 < 2 && x+x2 < width; x2++ {
// 						gray.SetGray(x+x2, y, color.Gray{(b >> 4) * 0x11})
// 						b <<= 4
// 					}
// 				}
// 			}
// 		case cbG8:
// 			if d.use_transparent {
// 				ty := d.transparent[1]
// 				for x := 0; x < width; x++ {
// 					ycol := cdat[x]
// 					acol := uint8(0xff)
// 					if ycol == ty {
// 						acol = 0x00
// 					}
// 					nrgba.SetNRGBA(x, y, color.NRGBA{ycol, ycol, ycol, acol})
// 				}
// 			} else {
// 				copy(gray.Pix[pix_offset:], cdat)
// 				pix_offset += gray.Stride
// 			}
// 		case cbGA8:
// 			for x := 0; x < width; x++ {
// 				ycol := cdat[2*x+0]
// 				nrgba.SetNRGBA(x, y, color.NRGBA{ycol, ycol, ycol, cdat[2*x+1]})
// 			}
// 		case CB_TC8:
// 			if d.use_transparent {
// 				pix, i, j := nrgba.Pix, pix_offset, 0
// 				tr, tg, tb := d.transparent[1], d.transparent[3], d.transparent[5]
// 				for x := 0; x < width; x++ {
// 					r := cdat[j+0]
// 					g := cdat[j+1]
// 					b := cdat[j+2]
// 					a := uint8(0xff)
// 					if r == tr && g == tg && b == tb {
// 						a = 0x00
// 					}
// 					pix[i+0] = r
// 					pix[i+1] = g
// 					pix[i+2] = b
// 					pix[i+3] = a
// 					i += 4
// 					j += 3
// 				}
// 				pix_offset += nrgba.Stride
// 			} else {
// 				pix, i, j := rgba.Pix, pix_offset, 0
// 				for x := 0; x < width; x++ {
// 					pix[i+0] = cdat[j+0]
// 					pix[i+1] = cdat[j+1]
// 					pix[i+2] = cdat[j+2]
// 					pix[i+3] = 0xff
// 					i += 4
// 					j += 3
// 				}
// 				pix_offset += rgba.Stride
// 			}
// 		case CB_P1:
// 			for x := 0; x < width; x += 8 {
// 				b := cdat[x/8]
// 				for x2 := 0; x2 < 8 && x+x2 < width; x2++ {
// 					idx := b >> 7
// 					if len(paletted.Palette) <= int(idx) {
// 						paletted.Palette = paletted.Palette[:int(idx)+1]
// 					}
// 					paletted.SetColorIndex(x+x2, y, idx)
// 					b <<= 1
// 				}
// 			}
// 		case cb_p2:
// 			for x := 0; x < width; x += 4 {
// 				b := cdat[x/4]
// 				for x2 := 0; x2 < 4 && x+x2 < width; x2++ {
// 					idx := b >> 6
// 					if len(paletted.Palette) <= int(idx) {
// 						paletted.Palette = paletted.Palette[:int(idx)+1]
// 					}
// 					paletted.SetColorIndex(x+x2, y, idx)
// 					b <<= 2
// 				}
// 			}
// 		case cb_p4:
// 			for x := 0; x < width; x += 2 {
// 				b := cdat[x/2]
// 				for x2 := 0; x2 < 2 && x+x2 < width; x2++ {
// 					idx := b >> 4
// 					if len(paletted.Palette) <= int(idx) {
// 						paletted.Palette = paletted.Palette[:int(idx)+1]
// 					}
// 					paletted.SetColorIndex(x+x2, y, idx)
// 					b <<= 4
// 				}
// 			}
// 		case CB_P8:
// 			if len(paletted.Palette) != 256 {
// 				for x := 0; x < width; x++ {
// 					if len(paletted.Palette) <= int(cdat[x]) {
// 						paletted.Palette = paletted.Palette[:int(cdat[x])+1]
// 					}
// 				}
// 			}
// 			copy(paletted.Pix[pix_offset:], cdat)
// 			pix_offset += paletted.Stride
// 		case CB_TCA8:
// 			copy(nrgba.Pix[pix_offset:], cdat)
// 			pix_offset += nrgba.Stride
// 		case cbG16:
// 			if d.use_transparent {
// 				ty := uint16(d.transparent[0])<<8 | uint16(d.transparent[1])
// 				for x := 0; x < width; x++ {
// 					ycol := uint16(cdat[2*x+0])<<8 | uint16(cdat[2*x+1])
// 					acol := uint16(0xffff)
// 					if ycol == ty {
// 						acol = 0x0000
// 					}
// 					nrgba64.SetNRGBA64(x, y, color.NRGBA64{ycol, ycol, ycol, acol})
// 				}
// 			} else {
// 				for x := 0; x < width; x++ {
// 					ycol := uint16(cdat[2*x+0])<<8 | uint16(cdat[2*x+1])
// 					gray16.SetGray16(x, y, color.Gray16{ycol})
// 				}
// 			}
// 		case cbGA16:
// 			for x := 0; x < width; x++ {
// 				ycol := uint16(cdat[4*x+0])<<8 | uint16(cdat[4*x+1])
// 				acol := uint16(cdat[4*x+2])<<8 | uint16(cdat[4*x+3])
// 				nrgba64.SetNRGBA64(x, y, color.NRGBA64{ycol, ycol, ycol, acol})
// 			}
// 		case CB_TC16:
// 			if d.use_transparent {
// 				tr := uint16(d.transparent[0])<<8 | uint16(d.transparent[1])
// 				tg := uint16(d.transparent[2])<<8 | uint16(d.transparent[3])
// 				tb := uint16(d.transparent[4])<<8 | uint16(d.transparent[5])
// 				for x := 0; x < width; x++ {
// 					rcol := uint16(cdat[6*x+0])<<8 | uint16(cdat[6*x+1])
// 					gcol := uint16(cdat[6*x+2])<<8 | uint16(cdat[6*x+3])
// 					bcol := uint16(cdat[6*x+4])<<8 | uint16(cdat[6*x+5])
// 					acol := uint16(0xffff)
// 					if rcol == tr && gcol == tg && bcol == tb {
// 						acol = 0x0000
// 					}
// 					nrgba64.SetNRGBA64(x, y, color.NRGBA64{rcol, gcol, bcol, acol})
// 				}
// 			} else {
// 				for x := 0; x < width; x++ {
// 					rcol := uint16(cdat[6*x+0])<<8 | uint16(cdat[6*x+1])
// 					gcol := uint16(cdat[6*x+2])<<8 | uint16(cdat[6*x+3])
// 					bcol := uint16(cdat[6*x+4])<<8 | uint16(cdat[6*x+5])
// 					rgba64.SetRGBA64(x, y, color.RGBA64{rcol, gcol, bcol, 0xffff})
// 				}
// 			}
// 		case CB_TCA16:
// 			for x := 0; x < width; x++ {
// 				rcol := uint16(cdat[8*x+0])<<8 | uint16(cdat[8*x+1])
// 				gcol := uint16(cdat[8*x+2])<<8 | uint16(cdat[8*x+3])
// 				bcol := uint16(cdat[8*x+4])<<8 | uint16(cdat[8*x+5])
// 				acol := uint16(cdat[8*x+6])<<8 | uint16(cdat[8*x+7])
// 				nrgba64.SetNRGBA64(x, y, color.NRGBA64{rcol, gcol, bcol, acol})
// 			}
// 		}

// 		// The current row for y is the previous row for y+1.
// 		pr, cr = cr, pr
// 	}

// 	return img, nil
// }

// // mergePassInto merges a single pass into a full sized image.
// func (d *decoder) mergePassInto(dst image.Image, src image.Image, pass int) {
// 	p := interlacing[pass]
// 	var (
// 		srcPix        []uint8
// 		dstPix        []uint8
// 		stride        int
// 		rect          image.Rectangle
// 		bytesPerPixel int
// 	)
// 	switch target := dst.(type) {
// 	case *image.Alpha:
// 		srcPix = src.(*image.Alpha).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 1
// 	case *image.Alpha16:
// 		srcPix = src.(*image.Alpha16).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 2
// 	case *image.Gray:
// 		srcPix = src.(*image.Gray).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 1
// 	case *image.Gray16:
// 		srcPix = src.(*image.Gray16).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 2
// 	case *image.NRGBA:
// 		srcPix = src.(*image.NRGBA).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 4
// 	case *image.NRGBA64:
// 		srcPix = src.(*image.NRGBA64).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 8
// 	case *image.Paletted:
// 		source := src.(*image.Paletted)
// 		srcPix = source.Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 1
// 		if len(target.Palette) < len(source.Palette) {
// 			// readImagePass can return a paletted image whose implicit palette
// 			// length (one more than the maximum Pix value) is larger than the
// 			// explicit palette length (what's in the PLTE chunk). Make the
// 			// same adjustment here.
// 			target.Palette = source.Palette
// 		}
// 	case *image.RGBA:
// 		srcPix = src.(*image.RGBA).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 4
// 	case *image.RGBA64:
// 		srcPix = src.(*image.RGBA64).Pix
// 		dstPix, stride, rect = target.Pix, target.Stride, target.Rect
// 		bytesPerPixel = 8
// 	}
// 	s, bounds := 0, src.Bounds()
// 	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
// 		dBase := (y*p.y_factor+p.y_offset-rect.Min.Y)*stride + (p.x_offset-rect.Min.X)*bytesPerPixel
// 		for x := bounds.Min.X; x < bounds.Max.X; x++ {
// 			d := dBase + x*p.x_factor*bytesPerPixel
// 			copy(dstPix[d:], srcPix[s:s+bytesPerPixel])
// 			s += bytesPerPixel
// 		}
// 	}
// }

// func (d *decoder) parseIDAT(length uint32) (err error) {
// 	d.idat_length = length
// 	d.img, err = d.decode()
// 	if err != nil {
// 		return err
// 	}
// 	return d.verifyChecksum()
// }

// func (d *decoder) parseIEND(length uint32) error {
// 	if length != 0 {
// 		return format_error("bad IEND length")
// 	}
// 	return d.verifyChecksum()
// }

// func (d *decoder) parseChunk(configOnly bool) error {
// 	// Read the length and chunk type.
// 	if _, err := io.ReadFull(d.r, d.tmp[:8]); err != nil {
// 		return err
// 	}
// 	length := binary.BigEndian.Uint32(d.tmp[:4])
// 	d.crc.Reset()
// 	d.crc.Write(d.tmp[4:8])

// 	// Read the chunk data.
// 	switch string(d.tmp[4:8]) {
// 	case "IHDR":
// 		if d.stage != DS_START {
// 			return chunk_order_error
// 		}
// 		d.stage = DS_SEEN_IHDR
// 		return d.parseIHDR(length)
// 	case "PLTE":
// 		if d.stage != DS_SEEN_IHDR {
// 			return chunk_order_error
// 		}
// 		d.stage = DS_SEEN_PLTE
// 		return d.parsePLTE(length)
// 	case "tRNS":
// 		if cb_paletted(d.cb) {
// 			if d.stage != DS_SEEN_PLTE {
// 				return chunk_order_error
// 			}
// 		} else if cb_true_color(d.cb) {
// 			if d.stage != DS_SEEN_IHDR && d.stage != DS_SEEN_PLTE {
// 				return chunk_order_error
// 			}
// 		} else if d.stage != DS_SEEN_IHDR {
// 			return chunk_order_error
// 		}
// 		d.stage = DS_SEENT_RNS
// 		return d.parsetRNS(length)
// 	case "IDAT":
// 		if d.stage < DS_SEEN_IHDR || d.stage > DS_SEEN_IDAT || (d.stage == DS_SEEN_IHDR && cb_paletted(d.cb)) {
// 			return chunk_order_error
// 		} else if d.stage == DS_SEEN_IDAT {
// 			// Ignore trailing zero-length or garbage IDAT chunks.
// 			//
// 			// This does not affect valid PNG images that contain multiple IDAT
// 			// chunks, since the first call to parseIDAT below will consume all
// 			// consecutive IDAT chunks required for decoding the image.
// 			break
// 		}
// 		d.stage = DS_SEEN_IDAT
// 		if configOnly {
// 			return nil
// 		}
// 		return d.parseIDAT(length)
// 	case "IEND":
// 		if d.stage != DS_SEEN_IDAT {
// 			return chunk_order_error
// 		}
// 		d.stage = DS_SEEN_IEND
// 		return d.parseIEND(length)
// 	}
// 	if length > 0x7fffffff {
// 		return format_error(fmt.Sprintf("Bad chunk length: %d", length))
// 	}
// 	// Ignore this chunk (of a known length).
// 	var ignored [4096]byte
// 	for length > 0 {
// 		n, err := io.ReadFull(d.r, ignored[:min(len(ignored), int(length))])
// 		if err != nil {
// 			return err
// 		}
// 		d.crc.Write(ignored[:n])
// 		length -= uint32(n)
// 	}
// 	return d.verifyChecksum()
// }

// func (d *decoder) verifyChecksum() error {
// 	if _, err := io.ReadFull(d.r, d.tmp[:4]); err != nil {
// 		return err
// 	}
// 	if binary.BigEndian.Uint32(d.tmp[:4]) != d.crc.Sum32() {
// 		return format_error("invalid checksum")
// 	}
// 	return nil
// }

// func (d *decoder) checkHeader() error {
// 	_, err := io.ReadFull(d.r, d.tmp[:len(PNG_HEADER)])
// 	if err != nil {
// 		return err
// 	}
// 	if string(d.tmp[:len(PNG_HEADER)]) != PNG_HEADER {
// 		return format_error("not a PNG file")
// 	}
// 	return nil
// }

// // Decode reads a PNG image from r and returns it as an [image.Image].
// // The type of Image returned depends on the PNG contents.
// func Decode(r io.Reader) (image.Image, error) {
// 	d := &decoder{
// 		r:   r,
// 		crc: crc32.NewIEEE(),
// 	}
// 	if err := d.checkHeader(); err != nil {
// 		if err == io.EOF {
// 			err = io.ErrUnexpectedEOF
// 		}
// 		return nil, err
// 	}
// 	for d.stage != DS_SEEN_IEND {
// 		if err := d.parseChunk(false); err != nil {
// 			if err == io.EOF {
// 				err = io.ErrUnexpectedEOF
// 			}
// 			return nil, err
// 		}
// 	}
// 	return d.img, nil
// }

// // DecodeConfig returns the color model and dimensions of a PNG image without
// // decoding the entire image.
// func DecodeConfig(r io.Reader) (image.Config, error) {
// 	d := &decoder{
// 		r:   r,
// 		crc: crc32.NewIEEE(),
// 	}
// 	if err := d.checkHeader(); err != nil {
// 		if err == io.EOF {
// 			err = io.ErrUnexpectedEOF
// 		}
// 		return image.Config{}, err
// 	}

// 	for {
// 		if err := d.parseChunk(true); err != nil {
// 			if err == io.EOF {
// 				err = io.ErrUnexpectedEOF
// 			}
// 			return image.Config{}, err
// 		}

// 		if cb_paletted(d.cb) {
// 			if d.stage >= DS_SEENT_RNS {
// 				break
// 			}
// 		} else {
// 			if d.stage >= DS_SEEN_IHDR {
// 				break
// 			}
// 		}
// 	}

// 	var cm color.Model
// 	switch d.cb {
// 	case cbG1, cbG2, cbG4, cbG8:
// 		cm = color.GrayModel
// 	case cbGA8:
// 		cm = color.NRGBAModel
// 	case CB_TC8:
// 		cm = color.RGBAModel
// 	case CB_P1, cb_p2, cb_p4, CB_P8:
// 		cm = d.palette
// 	case CB_TCA8:
// 		cm = color.NRGBAModel
// 	case cbG16:
// 		cm = color.Gray16Model
// 	case cbGA16:
// 		cm = color.NRGBA64Model
// 	case CB_TC16:
// 		cm = color.RGBA64Model
// 	case CB_TCA16:
// 		cm = color.NRGBA64Model
// 	}
// 	return image.Config{
// 		ColorModel: cm,
// 		Width:      d.width,
// 		Height:     d.height,
// 	}, nil
// }

// func init() {
// 	image.RegisterFormat("png", PNG_HEADER, Decode, DecodeConfig)
// }
