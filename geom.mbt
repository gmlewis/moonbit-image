// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/geom.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
/// A Point is an X, Y coordinate pair. The axes increase right and down.
pub(all) struct Point {
  mut x : Int
  mut y : Int
} derive(Show, Eq)

///|
/// to_string returns a string representation of p like "(3,4)".
pub fn to_string(self : Point) -> String {
  "(\{self.x},\{self.y})"
}

///|
/// op_add (+) returns the vector p+q.
pub impl Add for Point with op_add(self, q) {
  { x: self.x + q.x, y: self.y + q.y }
}

///|
/// op_sub (-) returns the vector p-q.
pub impl Sub for Point with op_sub(self, q) {
  { x: self.x - q.x, y: self.y - q.y }
}

///|
/// mul returns the vector p*k.
pub fn mul(self : Point, k : Int) -> Point {
  { x: self.x * k, y: self.y * k }
}

///|
/// div returns the vector p/k.
pub fn div(self : Point, k : Int) -> Point {
  { x: self.x / k, y: self.y / k }
}

///|
/// is_in reports whether p is in r.
pub fn is_in(self : Point, r : Rectangle) -> Bool {
  r.min.x <= self.x && self.x < r.max.x && r.min.y <= self.y && self.y < r.max.y
}

///|
/// mod returns the point q in r such that p.X-q.X is a multiple of r's width
/// and p.Y-q.Y is a multiple of r's height.
pub fn mod(self : Point, r : Rectangle) -> Point {
  let (w, h) = (r.dx(), r.dy())
  let p = self - r.min
  p.x = p.x % w
  if p.x < 0 {
    p.x += w
  }
  p.y = p.y % h
  if p.y < 0 {
    p.y += h
  }
  p + r.min
}

///|
/// pt is shorthand for [Point]{X, Y}.
pub fn pt(x : Int, y : Int) -> Point {
  { x, y }
}

///|
/// A Rectangle contains the points with Min.X <= X < Max.X, Min.Y <= Y < Max.Y.
/// It is well-formed if Min.X <= Max.X and likewise for Y. Points are always
/// well-formed. A rectangle's methods always return well-formed outputs for
/// well-formed inputs.
///
/// A Rectangle is also an [Image] whose bounds are the rectangle itself. At
/// returns color.Opaque for points in the rectangle and color.Transparent
/// otherwise.
pub(all) struct Rectangle {
  min : Point
  max : Point
} derive(Show)

///|
/// `Rectangle` satisfies the `Image` trait.
let _Rectangle : &Image = Rectangle::new()

///|
/// Rectangle::new returns an empty (all zeros) rectangle.
pub fn Rectangle::new() -> Rectangle {
  { min: pt(0, 0), max: pt(0, 0) }
}

///|
pub impl Image for Rectangle with opaque_(_self) {
  true
}

///|
pub impl Image for Rectangle with set(_self, _x, _y, _c) {

}

///|
pub impl Image for Rectangle with sub_image(self, _o) {
  self
}

///|
pub impl Image for Rectangle with raw_data(_self) {
  Slice::new([])
}

///|
pub impl Image for Rectangle with get_bytes_per_pixel(_self) {
  0
}

///|
pub impl Image for Rectangle with get_stride(_self) {
  0
}

///|
pub impl Image for Rectangle with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for Rectangle with pix_offset(_self, _x, _y) {
  0
}

///|
/// copy makes a copy of the provided rectangle without changing it.
pub fn copy(self : Rectangle) -> Rectangle {
  { min: pt(self.min.x, self.min.y), max: pt(self.max.x, self.max.y) }
}

///|
/// to_string returns a string representation of r like "(3,4)-(6,5)".
pub fn Rectangle::to_string(self : Rectangle) -> String {
  "\{self.min}-\{self.max}"
}

///|
/// dx returns r's width.
pub fn dx(self : Rectangle) -> Int {
  self.max.x - self.min.x
}

///|
/// dy returns r's height.
pub fn dy(self : Rectangle) -> Int {
  self.max.y - self.min.y
}

///|
/// size returns r's width and height.
pub fn size(self : Rectangle) -> Point {
  { x: self.max.x - self.min.x, y: self.max.y - self.min.y }
}

///|
/// add returns the rectangle r translated by p.
pub fn add(self : Rectangle, p : Point) -> Rectangle {
  {
    min: pt(self.min.x + p.x, self.min.y + p.y),
    max: pt(self.max.x + p.x, self.max.y + p.y),
  }
}

///|
/// sub returns the rectangle r translated by -p.
pub fn sub(self : Rectangle, p : Point) -> Rectangle {
  {
    min: pt(self.min.x - p.x, self.min.y - p.y),
    max: pt(self.max.x - p.x, self.max.y - p.y),
  }
}

///|
/// inset returns the rectangle r inset by n, which may be negative. If either
/// of r's dimensions is less than 2*n then an empty rectangle near the center
/// of r will be returned.
pub fn inset(self : Rectangle, n : Int) -> Rectangle {
  let r = self.copy()
  if r.dx() < 2 * n {
    r.min.x = (r.min.x + r.max.x) / 2
    r.max.x = r.min.x
  } else {
    r.min.x += n
    r.max.x -= n
  }
  if r.dy() < 2 * n {
    r.min.y = (r.min.y + r.max.y) / 2
    r.max.y = r.min.y
  } else {
    r.min.y += n
    r.max.y -= n
  }
  r
}

///|
/// intersect returns the largest rectangle contained by both r and s. If the
/// two rectangles do not overlap then the zero rectangle will be returned.
pub fn intersect(self : Rectangle, s : Rectangle) -> Rectangle {
  let r = self.copy()
  if r.min.x < s.min.x {
    r.min.x = s.min.x
  }
  if r.min.y < s.min.y {
    r.min.y = s.min.y
  }
  if r.max.x > s.max.x {
    r.max.x = s.max.x
  }
  if r.max.y > s.max.y {
    r.max.y = s.max.y
  }
  // Letting r0 and s0 be the values of r and s at the time that the method
  // is called, this next line is equivalent to:
  //
  // if max(r0.Min.X, s0.Min.X) >= min(r0.Max.X, s0.Max.X) || likewiseForY { etc }
  if r.empty() {
    return Rectangle::new()
  }
  r
}

///|
/// union returns the smallest rectangle that contains both r and s.
pub fn union(self : Rectangle, s : Rectangle) -> Rectangle {
  let r = self.copy()
  if r.empty() {
    return s
  }
  if s.empty() {
    return r
  }
  if r.min.x > s.min.x {
    r.min.x = s.min.x
  }
  if r.min.y > s.min.y {
    r.min.y = s.min.y
  }
  if r.max.x < s.max.x {
    r.max.x = s.max.x
  }
  if r.max.y < s.max.y {
    r.max.y = s.max.y
  }
  r
}

///|
/// empty reports whether the rectangle contains no points.
pub fn empty(self : Rectangle) -> Bool {
  self.min.x >= self.max.x || self.min.y >= self.max.y
}

///|
/// op_equal reports whether r and s contain the same set of points. All empty
/// rectangles are considered equal.
pub impl Eq for Rectangle with op_equal(self, s) {
  (self.min == s.min && self.max == s.max) || (self.empty() && s.empty())
}

///|
/// overlaps reports whether r and s have a non-empty intersection.
pub fn overlaps(self : Rectangle, s : Rectangle) -> Bool {
  not(self.empty()) &&
  not(s.empty()) &&
  self.min.x < s.max.x &&
  s.min.x < self.max.x &&
  self.min.y < s.max.y &&
  s.min.y < self.max.y
}

///|
/// is_in reports whether every point in r is in s.
pub fn Rectangle::is_in(self : Rectangle, s : Rectangle) -> Bool {
  if self.empty() {
    return true
  }
  // note that self.max is an exclusive bound for r, so that self.in(s)
  // does not require that self.max.in(s).
  s.min.x <= self.min.x &&
  self.max.x <= s.max.x &&
  s.min.y <= self.min.y &&
  self.max.y <= s.max.y
}

///|
/// canon returns the canonical version of r. The returned rectangle has minimum
/// and maximum coordinates swapped if necessary so that it is well-formed.
pub fn canon(self : Rectangle) -> Rectangle {
  let r = self.copy()
  if r.max.x < r.min.x {
    let tmp = r.min.x
    r.min.x = r.max.x
    r.max.x = tmp
  }
  if r.max.y < r.min.y {
    let tmp = r.min.y
    r.min.y = r.max.y
    r.max.y = tmp
  }
  r
}

///|
/// at implements the [Image] trait.
pub impl Image for Rectangle with at(self, x, y) {
  if pt(x, y).is_in(self) {
    return @color.opaque_
  }
  @color.transparent
}

///|
/// rgba64_at implements the [RGBA64Image] trait.
pub fn rgba64_at(self : Rectangle, x : Int, y : Int) -> @color.RGBA64 {
  if pt(x, y).is_in(self) {
    return @color.RGBA64::{ r: 0xffff, g: 0xffff, b: 0xffff, a: 0xffff }
  }
  @color.RGBA64::{ r: 0, g: 0, b: 0, a: 0 }
}

///|
/// bounds implements the [Image] trait.
pub impl Image for Rectangle with bounds(self) {
  self
}

///|
/// color_model implements the [Image] trait.
pub impl Image for Rectangle with color_model(_self) {
  @color.alpha16_model
}

///|
/// rect is shorthand for [Rectangle]{Pt(x0, y0), [Pt](x1, y1)}. The returned
/// rectangle has minimum and maximum coordinates swapped if necessary so that
/// it is well-formed.
pub fn rect(x0 : Int, y0 : Int, x1 : Int, y1 : Int) -> Rectangle {
  let (x0, x1) = if x0 > x1 { (x1, x0) } else { (x0, x1) }
  let (y0, y1) = if y0 > y1 { (y1, y0) } else { (y0, y1) }
  { min: pt(x0, y0), max: pt(x1, y1) }
}

///|
/// mul3_non_neg returns (x * y * z), unless at least one argument is negative or
/// if the computation overflows the int type, in which case it returns -1.
pub fn mul3_non_neg(x : Int, y : Int, z : Int) -> Int {
  if x < 0 || y < 0 || z < 0 {
    return -1
  }
  let v = BigInt::from_int(x) * BigInt::from_int(y) * BigInt::from_int(z)
  if v > BigInt::from_int(@int.max_value) {
    return -1
  }
  let s = v.to_string()
  @strconv.parse_int(s) catch {
    _ => return -1
  }
}

///|
/// add2_non_neg returns (x + y), unless at least one argument is negative or if
/// the computation overflows the int type, in which case it returns -1.
pub fn add2_non_neg(x : Int, y : Int) -> Int {
  if x < 0 || y < 0 {
    return -1
  }
  let a = x + y
  if a < 0 {
    return -1
  }
  a
}
