package fs

import "core:fmt"
import "core:os"
import gl "vendor:OpenGL"

fs_load_shader :: proc(folder: string) -> (program: u32, ok: bool) {
  vertex_path := fmt.tprintf("%s/vertex.glsl", folder)
  vertex_code, vertex_ok := os.read_entire_file(vertex_path, context.allocator)
  if vertex_ok != nil {
    fmt.printfln("error opening shader file: %s", vertex_path)
    os.exit(1)
  }
  defer delete(vertex_code)

  frag_path := fmt.tprintf("%s/fragment.glsl", folder)
  frag_code, frag_ok := os.read_entire_file(frag_path, context.allocator)
  if frag_ok != nil {
    fmt.printfln("error opening shader file: %s", frag_path)
    os.exit(1)
  }
  defer delete(frag_code)

  /* compile and link the source straight onto the gpu pipeline */
  return gl.load_shaders_source(string(vertex_code), string(frag_code))
}
