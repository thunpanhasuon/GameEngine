package memory
import object "../object"
import "core:mem"

buf: [1024 * 1024]byte 
/* global heap */
heap: mem.Arena

memory_init :: proc(n: i32) -> []object.GameObject {
    mem.arena_init(&heap, buf[:])
    allocator := mem.arena_allocator(&heap)
    obj := make([]object.GameObject, n, allocator)
    return obj
}

memory_free :: proc() {
    mem.arena_free_all(&heap)
}