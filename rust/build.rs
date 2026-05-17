fn main() {
    #[cfg(all(windows, any(target_arch = "x86_64", target_arch = "x86")))]
    {
        thunk::thunk();
    }
}
