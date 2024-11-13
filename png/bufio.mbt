/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/bufio.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.
///
/// Package bufio implements buffered I/O. It wraps an io.Reader or io.Writer
/// object, creating another object (Reader or Writer) that also implements
/// the interface but provides buffering and some help for textual I/O.

const DEFAULT_BUF_SIZE = 4096

// ReaderSize implements buffering for an io.Reader object.
struct ReaderSize {
  mut buf : Slice[Byte]
  // reader provided by the client
  mut rd : @io.Reader
  // buf read and write positions
  mut r : Int
  mut w : Int
  mut err : IOError?
  // last byte read for UnreadByte; -1 means invalid
  mut last_byte : Int
  // size of last rune read for UnreadRune; -1 means invalid
  // lastRuneSize : Int
}

const MIN_READ_BUFFER_SIZE = 16

const MAX_CONSECUTIVE_EMPTY_READS = 100

// `ReaderSize::new` returns a new [Reader] whose buffer has at least the specified
// size. If the argument io.Reader is already a [Reader] with large enough
// size, it returns the underlying [Reader].
fn ReaderSize::new(rd : @io.Reader, size : Int) -> ReaderSize {
  // Is it already a Reader?
  // b, ok := rd.(*Reader)
  // if ok && len(b.buf) >= size {
  // 	return b
  // }
  let r = { buf: Slice::new([]), rd, r: 0, w: 0, err: None, last_byte: -1 }
  // lastRuneSize: -1,
  r.reset_buf(
    Slice::new(Array::make(@math.maximum(size, MIN_READ_BUFFER_SIZE), b'\x00')),
    rd,
  )
  r
}

fn reset_buf(self : ReaderSize, buf : Slice[Byte], r : @io.Reader) -> Unit {
  self.buf = buf
  self.rd = r
  self.last_byte = -1
  // 		self.lastRuneSize: -1,
}

pub let err_negative_read : IOError = IOError(
  "bufio: reader returned negative count from read",
)

// fill reads a new chunk into the buffer.
fn fill(self : ReaderSize) -> IOError? {
  // Slide existing data to beginning.
  if self.r > 0 {
    let _ = slice_copy(self.buf, self.buf[self.r:self.w])
    self.w -= self.r
    self.r = 0
  }
  if self.w >= self.buf.length() {
    return Some(IOError("bufio: tried to fill full buffer"))
  }

  // Read new data: try a limited number of times.
  for i = MAX_CONSECUTIVE_EMPTY_READS; i > 0; i = i - 1 {
    let (n, err) = self.rd.read(self.buf[self.w:])
    if n < 0 {
      return Some(err_negative_read)
    }
    self.w += n
    if err != None {
      self.err = err
      return None
    }
    if n > 0 {
      return None
    }
  }
  Some(@io.err_no_progress)
}

fn read_err(self : ReaderSize) -> IOError? {
  let err = self.err
  self.err = None
  err
}

// read reads data into p.
// It returns the number of bytes read into p.
// The bytes are taken from at most one Read on the underlying [Reader],
// hence n may be less than len(p).
// To read exactly len(p) bytes, use io.ReadFull(b, p).
// If the underlying [Reader] can return a non-zero count with io.EOF,
// then this Read method can do so as well; see the [io.Reader] docs.
fn read(self : ReaderSize, p : Slice[Byte]) -> (Int, IOError?) {
  let mut n = p.length()
  if n == 0 {
    if self.buffered() > 0 {
      return (0, None)
    }
    return (0, self.read_err())
  }
  if self.r == self.w {
    if self.err != None {
      return (0, self.read_err())
    }
    if p.length() >= self.buf.length() {
      // Large read, empty buffer.
      // Read directly into p to avoid copy.
      let tmp = self.rd.read(p)
      n = tmp.0
      self.err = tmp.1
      if n < 0 {
        return (0, Some(err_negative_read))
      }
      if n > 0 {
        self.last_byte = p[n - 1].to_int()
        // self.lastRuneSize = -1
      }
      return (n, self.read_err())
    }
    // One read.
    // Do not use self.fill, which will loop.
    self.r = 0
    self.w = 0
    let tmp = self.rd.read(self.buf)
    n = tmp.0
    self.err = tmp.1
    if n < 0 {
      return (0, Some(err_negative_read))
    }
    if n == 0 {
      return (0, self.read_err())
    }
    self.w += n
  }

  // copy as much as we can
  // Note: if the slice panics here, it is probably because
  // the underlying reader returned a bad count. See issue 49795.
  n = slice_copy(p, self.buf[self.r:self.w])
  self.r += n
  self.last_byte = self.buf[self.r - 1].to_int()
  // self.lastRuneSize = -1
  (n, None)
}

// read_byte reads and returns a single byte.
// If no byte is available, returns an error.
fn read_byte(self : ReaderSize) -> (Byte, IOError?) {
  // self.lastRuneSize = -1
  while self.r == self.w {
    if self.err != None {
      return (0, self.read_err())
    }
    self.err = self.fill() // buffer is empty
  }
  let c = self.buf[self.r]
  self.r += 1
  self.last_byte = c.to_int()
  (c, None)
}

// Buffered returns the number of bytes that can be read from the current buffer.
fn buffered(self : ReaderSize) -> Int {
  self.w - self.r
}
