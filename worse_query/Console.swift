//
//  Console.swift
//  worse_query
//
//  Created by Taj C on 9/2/26.
//

import Foundation
import Combine

// I ended up completely redoing the logging setup this time around.
class Console: ObservableObject {
    @Published var output = ""
    
    private var pipe: Pipe?
    private var originalOut: Int32 = 0
    
    func start() {
        // Make a new pipe
        let newPipe = Pipe()
        pipe = newPipe
        // Save original stdout fd
        originalOut = dup(STDOUT_FILENO)
        
        // Redirect to our pipe
        dup2(newPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        setvbuf(stdout, nil, _IONBF, 0)
        
        // Read from our pipe
        newPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            
            // Write to stdout
            if let self = self {
                data.withUnsafeBytes { rawBuffer in
                    _ = write(self.originalOut, rawBuffer.baseAddress, data.count)
                }
            }
            
            // Write stdout to our output var
            if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                DispatchQueue.main.async {
                    self?.output += string
                }
            }
        }
        
        print("hello world (again)")
    }
}
