//! Just enough of the protobuf wire format to pick numbered fields out of a
//! message whose schema is not published. Malformed input ends the walk
//! instead of panicking.

pub enum Value<'a> {
    Varint(u64),
    Bytes(&'a [u8]),
    Fixed,
}

/// Every top-level `(field number, value)` in `buf`, in order.
pub fn fields(buf: &[u8]) -> impl Iterator<Item = (u64, Value<'_>)> {
    let mut rest = buf;
    std::iter::from_fn(move || {
        let key = take_varint(&mut rest)?;
        let value = match key & 7 {
            0 => Value::Varint(take_varint(&mut rest)?),
            1 => take_fixed(&mut rest, 8)?,
            2 => {
                let len = usize::try_from(take_varint(&mut rest)?).ok()?;
                let bytes = rest.get(..len)?;
                rest = &rest[len..];
                Value::Bytes(bytes)
            }
            5 => take_fixed(&mut rest, 4)?,
            _ => return None,
        };
        Some((key >> 3, value))
    })
}

/// The first varint field numbered `number`.
pub fn varint(buf: &[u8], number: u64) -> Option<u64> {
    fields(buf).find_map(|(n, value)| match value {
        Value::Varint(v) if n == number => Some(v),
        _ => None,
    })
}

/// The first length-delimited field numbered `number`: a nested message.
pub fn message(buf: &[u8], number: u64) -> Option<&[u8]> {
    fields(buf).find_map(|(n, value)| match value {
        Value::Bytes(bytes) if n == number => Some(bytes),
        _ => None,
    })
}

fn take_varint(rest: &mut &[u8]) -> Option<u64> {
    let mut value = 0u64;
    for (index, byte) in rest.iter().enumerate().take(10) {
        value |= u64::from(byte & 0x7f) << (7 * index);
        if byte & 0x80 == 0 {
            *rest = &rest[index + 1..];
            return Some(value);
        }
    }
    None
}

fn take_fixed<'a>(rest: &mut &'a [u8], len: usize) -> Option<Value<'a>> {
    rest.get(..len)?;
    *rest = &rest[len..];
    Some(Value::Fixed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_varints_and_nested_messages() {
        // {1: {1: 1789064060}, 3: 2, 9: {1: 1318, 3: 621}}
        let inner = [0x08, 0xfc, 0xe6, 0x8b, 0xd5, 0x06];
        let usage = [0x08, 0xa6, 0x0a, 0x18, 0xed, 0x04];
        let mut buf = vec![0x0a, inner.len() as u8];
        buf.extend_from_slice(&inner);
        buf.extend_from_slice(&[0x18, 0x02, 0x4a, usage.len() as u8]);
        buf.extend_from_slice(&usage);

        assert_eq!(message(&buf, 1).and_then(|m| varint(m, 1)), Some(1_789_064_060));
        assert_eq!(varint(&buf, 3), Some(2));
        let usage = message(&buf, 9).expect("usage");
        assert_eq!((varint(usage, 1), varint(usage, 3)), (Some(1318), Some(621)));
        assert!(message(&buf, 7).is_none());
    }

    #[test]
    fn fixed_width_fields_are_stepped_over() {
        let buf = [0x09, 1, 2, 3, 4, 5, 6, 7, 8, 0x15, 1, 2, 3, 4, 0x18, 0x07];
        assert_eq!(varint(&buf, 3), Some(7));
    }

    #[test]
    fn truncated_input_ends_the_walk() {
        assert!(message(&[0x0a, 0x05, 0x01], 1).is_none());
        assert!(varint(&[0x08, 0x80], 1).is_none());
        assert_eq!(fields(&[0x0f]).count(), 0);
    }
}
