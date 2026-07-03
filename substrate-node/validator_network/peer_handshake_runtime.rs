pub fn validate_handshake(version: &str) -> bool {
    version.starts_with("clrty/")
}
