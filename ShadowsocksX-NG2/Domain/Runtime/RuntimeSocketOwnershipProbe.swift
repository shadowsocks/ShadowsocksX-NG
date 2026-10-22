import Darwin

/// Read the kernel's descriptor table to distinguish a candidate listener from
/// another process that happens to answer on the same shared port.
enum RuntimeSocketOwnershipProbe {
  static func process(_ processID: Int32, ownsTCPListenerOn port: Int) -> Bool {
    guard processID > 0, (1...65535).contains(port) else { return false }

    let requiredBytes = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, nil, 0)
    let descriptorSize = MemoryLayout<proc_fdinfo>.size
    guard requiredBytes >= descriptorSize else { return false }

    var descriptors = [proc_fdinfo](
      repeating: proc_fdinfo(), count: Int(requiredBytes) / descriptorSize)
    let returnedBytes = descriptors.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else { return Int32(0) }
      return proc_pidinfo(
        processID,
        PROC_PIDLISTFDS,
        0,
        UnsafeMutableRawPointer(baseAddress),
        Int32(buffer.count * descriptorSize))
    }
    guard returnedBytes >= descriptorSize else { return false }

    let descriptorCount = min(Int(returnedBytes) / descriptorSize, descriptors.count)
    for descriptor in descriptors.prefix(descriptorCount)
    where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
      var socketInfo = socket_fdinfo()
      let socketInfoSize = MemoryLayout<socket_fdinfo>.size
      let socketInfoBytes = proc_pidfdinfo(
        processID,
        descriptor.proc_fd,
        PROC_PIDFDSOCKETINFO,
        &socketInfo,
        Int32(socketInfoSize))
      guard socketInfoBytes == socketInfoSize else { continue }

      let socket = socketInfo.psi
      guard socket.soi_kind == SOCKINFO_TCP,
        socket.soi_type == SOCK_STREAM,
        socket.soi_protocol == IPPROTO_TCP,
        socket.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
      else {
        continue
      }

      let rawPort = UInt16(truncatingIfNeeded: socket.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
      if Int(UInt16(bigEndian: rawPort)) == port { return true }
    }

    return false
  }
}
