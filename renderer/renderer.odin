package renderer

import fmt "core:fmt"
import math "core:math/linalg"
import gl "vendor:OpenGL"

import colors "../colors"
import fs "../fs"

vertices := []f32{
  -0.5, -0.5, 0.0,  // bl
  0.5, -0.5, 0.0,   // br
  0.5, 0.5, 0.0,    // tr
  -0.5, 0.5, 0.0,   // tl
}
indices := [6]u32{
  0, 1, 3,
  1, 2, 3,
}

triangle_vertices := []f32{
  0.0, 0.5, 0.0,    // top
  -0.5, -0.5, 0.0,  // bl
  0.5, -0.5, 0.0,   // br
}

GpuData :: struct {
  vao:     u32,
  vbo:     u32,
  ebo:     u32,
  program: u32,
}
TriangleGpuData :: struct {
  vao:     u32,
  vbo:     u32,
  program: u32,
}
GpuVertexData :: struct {
  mvp_location:     i32,
  u_color_location: i32,
}

gpu:                 GpuData
gpu_triangle:        TriangleGpuData
gpu_vertex:          GpuVertexData
gpu_vertex_triangle: GpuVertexData

/* the ortho projection needs the window size, and callers only know it once
   -- set it here rather than importing main's constants back into renderer */
window_width:  f32
window_height: f32

init :: proc(width: f32, height: f32) {
  window_width = width
  window_height = height

  set_gpu_data()
  create_quad()
  set_triangle_gpu_data()
  create_triangle()
  find_location()
  gl.UseProgram(gpu.program)
}

@(private)
set_gpu_data :: proc() {
  gl.GenVertexArrays(1, &gpu.vao)
  gl.GenBuffers(1, &gpu.vbo)
  gl.GenBuffers(1, &gpu.ebo)
  gl.BindVertexArray(gpu.vao)

  gl.BindBuffer(gl.ARRAY_BUFFER, gpu.vbo)
  gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)

  gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gpu.ebo)
  gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)

  POSITION_COMPONENTS :: 3 // x, y, z
  gl.VertexAttribPointer(0, POSITION_COMPONENTS, gl.FLOAT, false, POSITION_COMPONENTS * size_of(f32), 0)
  gl.EnableVertexAttribArray(0)
}

@(private)
set_triangle_gpu_data :: proc() {
  gl.GenVertexArrays(1, &gpu_triangle.vao)
  gl.GenBuffers(1, &gpu_triangle.vbo)
  gl.BindVertexArray(gpu_triangle.vao)

  gl.BindBuffer(gl.ARRAY_BUFFER, gpu_triangle.vbo)
  gl.BufferData(gl.ARRAY_BUFFER, len(triangle_vertices) * size_of(triangle_vertices[0]), raw_data(triangle_vertices), gl.STATIC_DRAW)

  POSITION_COMPONENTS :: 3 // x, y, z
  gl.VertexAttribPointer(0, POSITION_COMPONENTS, gl.FLOAT, false, POSITION_COMPONENTS * size_of(f32), 0)
  gl.EnableVertexAttribArray(0)
}

@(private)
create_quad :: proc() {
  ok: bool
  gpu.program, ok = fs.fs_load_shader("shaders/quad")
  if !ok {
    fmt.println("shader compile failed")
  }
  fmt.println("shader program:", gpu.program, "ok:", ok)
}

@(private)
create_triangle :: proc() {
  ok: bool
  gpu_triangle.program, ok = fs.fs_load_shader("shaders/triangle")
  if !ok {
    fmt.println("shader compile failed")
  }
  fmt.println("triangle shader program:", gpu_triangle.program, "ok:", ok)
}

@(private)
find_location :: proc() {
  gpu_vertex.mvp_location = gl.GetUniformLocation(gpu.program, "mvp")
  gpu_vertex.u_color_location = gl.GetUniformLocation(gpu.program, "uColor")
  gpu_vertex_triangle.mvp_location = gl.GetUniformLocation(gpu_triangle.program, "mvp")
  gpu_vertex_triangle.u_color_location = gl.GetUniformLocation(gpu_triangle.program, "uColor")
}

draw_rect :: proc(x: f32, y: f32, w: f32, h: f32, color: colors.Lofi_Color) {

  /* calucated matrix model */
  model: matrix[4, 4]f32 = 1.0
  /* quad vertices are centered on the origin (-0.5..0.5), but x/y here
     is the top-left corner (matches Box / collision convention), so
     shift the pivot by half the box size */
  transation := math.matrix4_translate_f32({x + w * 0.5, y + h * 0.5, 0.0})
  scale := math.matrix4_scale_f32({w, h, 0.0})
  model = transation * scale

  /* projection */
  proj := math.matrix_ortho3d_f32(0, window_width, window_height, 0, -1, 1)

  /* model view projection */
  mvp_matrix: matrix[4, 4]f32
  mvp_matrix = proj * model

  gl.UseProgram(gpu.program)
  gl.UniformMatrix4fv(gpu_vertex.mvp_location, 1, gl.FALSE, &mvp_matrix[0, 0])
  rgba := colors.rgba(color)
  gl.Uniform4fv(gpu_vertex.u_color_location, 1, &rgba[0])
  /* one lookup, then hand the whole rgba to the shader */
  gl.BindVertexArray(gpu.vao)
  gl.DrawElements(gl.TRIANGLES, len(indices), gl.UNSIGNED_INT, nil)
}

draw_triangle :: proc(x: f32, y: f32, w: f32, h: f32, color: colors.Lofi_Color) {

  model: matrix[4, 4]f32 = 1.0
  transation := math.matrix4_translate_f32({x + w * 0.5, y + h * 0.5, 0.0})
  scale := math.matrix4_scale_f32({w, h, 0.0})
  model = transation * scale

  proj := math.matrix_ortho3d_f32(0, window_width, window_height, 0, -1, 1)

  mvp_matrix: matrix[4, 4]f32
  mvp_matrix = proj * model

  gl.UseProgram(gpu_triangle.program)
  gl.UniformMatrix4fv(gpu_vertex_triangle.mvp_location, 1, gl.FALSE, &mvp_matrix[0, 0])
  rgba := colors.rgba(color)
  gl.Uniform4fv(gpu_vertex_triangle.u_color_location, 1, &rgba[0])
  gl.BindVertexArray(gpu_triangle.vao)
  gl.DrawArrays(gl.TRIANGLES, 0, 3)
}
