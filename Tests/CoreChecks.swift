do {
    guard FolderOrdering.Verify() else { fatalError("View ordering regression failed") }
    for result in try FileOperations.Verify() { print("PASS: \(result)") }
    print("PASS: view ordering and filtering")
} catch { fatalError("Core verification failed: \(error)") }
