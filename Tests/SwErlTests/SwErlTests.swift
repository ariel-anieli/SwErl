//
//  SwErlTests.swift
//
//Copyright (c) 2023 Lee Barney
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.
//
//  Created by Lee Barney on 2/24/23.
//

import XCTest
@testable import SwErl



final class SwErlTests: XCTestCase {
    
    override func setUp() {
        
        // Clear the Registrar and the counter for the PIDs
        Registrar.instance.processesLinkedToPid = [:]
        pidCounter = ProcessIDCounter()
     }
    
    override func tearDown() {
        // Clear the Registrar and the counter for the PIDs
        Registrar.instance.processesLinkedToPid = [:]
        pidCounter = ProcessIDCounter()
     }
    
    func testPidCounter() throws {
        for n in 1..<10{
            let (count,_)=pidCounter.next()
            XCTAssertEqual(UInt32(n), count)
        }
    }
    func testPidCounterRollover() throws{
        //get it ready for a rollover
        pidCounter.value = UInt32.max - 1
        pidCounter.creation = 0
        let (count,creation) = pidCounter.next()
        XCTAssertEqual(0, count)
        XCTAssertEqual(1, creation)
    }
    
    
    func testHappyPathSpawnStateless() throws {
        let PID = try spawn{(PID, message) in
            print("hello \(message)")
            return
        }
        XCTAssertEqual(1,Registrar.instance.processesLinkedToPid.count)
        XCTAssertEqual(Pid(id: 0, serial: 1, creation: 0), PID)
    }
    
    
    func testHappyPathSpawnStateful() throws {
        let _ = try spawn(initialState: 3){(procName, message,state) in
            return (true,5)
        }
        XCTAssertEqual(1,Registrar.instance.processesLinkedToPid.count)
        
    }
    func testHappyPathSpawnWithName() throws {
        _ = try spawn(name:"silly"){(PID, message) in
            print("hello \(message)")
            return
        }
        XCTAssertEqual(1,Registrar.instance.processesLinkedToName.count)
    }
    
    
    func testSendMessageUsingName() throws {
        let expectation = XCTestExpectation(description: "send completed.")
        let _ = try spawn(name:"silly"){(PID, message) in
            expectation.fulfill()
            return
        }
        "silly" ! 5
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testSendMessageUsingPid() throws {
        let expectation = XCTestExpectation(description: "send completed.")
        let Pid = try spawn{(PID, message) in
            expectation.fulfill()
            return
        }
        Pid ! 5
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testNotRegisteredPid() throws{
        XCTAssertNoThrow(Pid(id: 0, serial: 0, creation: 0) ! "hello")
    }
    func testChainingByCapture() throws{
        //don't let the test end until the last process
        //executes
        let expectation = XCTestExpectation(description: "second completed.")
        let secondPid = try spawn{(PID, message) in
            print("goodbye \(message)")
            expectation.fulfill()
            return
        }
        //capture the next pid
        let initialPid = try spawn{(PID, message) in
            print("hello \(message)")
            secondPid ! message
            return
        }
        XCTAssertEqual(2, Registrar.instance.processesLinkedToPid.count)
        
        initialPid ! "Sue"
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testRawChainingByList() throws {
        
        let expectation = XCTestExpectation(description: "all completed.")
        
        let initialPid = try spawn{(PID, message) in
            var (chain,data) = message as! ([Pid], Int)
            XCTAssertEqual(data, 2)
            chain.removeFirst() ! (chain,data + 3)
            return
        }
        let secondPid = try spawn{(PID, message) in
            var (chain,data) = message as! ([Pid], Int)
            XCTAssertEqual(data, 5)
            chain.removeFirst() ! (chain,data * 5)
            return
        }
        let finalPid = try spawn{(PID, message) in
            let (_,data) = message as! ([Pid], Int)
            XCTAssertEqual(data, 25)
            expectation.fulfill()
            return
        }
        let chain = [secondPid,finalPid]
        
        initialPid ! (chain,2)
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testSendMessageToStatelessProcess() throws {
        let anID = Pid(id: 0, serial: 1, creation: 0)
        
        let stateless = try SwErlProcess(registrationID: anID){(name, message) in
            return
        }
        XCTAssertNoThrow(try Registrar.link(stateless, PID: anID))
        XCTAssertNoThrow(anID ! "hello")
        XCTAssertNotNil(Registrar.instance.processesLinkedToPid[anID])
        
        let stopperID = Pid(id: 0, serial: 2, creation: 0)
        let stopper = try SwErlProcess(registrationID: stopperID){(name, message) in
            return
        }
        XCTAssertNoThrow(try Registrar.link(stopper, PID: stopperID))
        XCTAssertNoThrow(stopperID ! "hello")
        
        XCTAssertNotNil(Registrar.instance.processesLinkedToPid[stopperID])
        XCTAssertEqual(2, Registrar.instance.processesLinkedToPid.count)
    }
    
    func testStatelessSwerlProcessWithDefaults() throws {
        let bingo = Pid(id: 0, serial: 1, creation: 0)
        let stateless = try SwErlProcess(registrationID: bingo){(name, message) in
            return
        }
        XCTAssertNil(stateless.statefulLambda)
        XCTAssertNil(stateless.state)
        XCTAssertEqual(stateless.queue, DispatchQueue.global())
        XCTAssertEqual(stateless.registeredPid, bingo)
        XCTAssertNotNil(stateless.statelessLambda)
        XCTAssertNoThrow(stateless.statelessLambda!(bingo,3))
    }
    
    func testStatelessSwerlProcessNoDefaults() throws {
        let mainBingo = Pid(id: 0, serial: 1, creation: 0)
        let stateless = try SwErlProcess(queueToUse:DispatchQueue.main, registrationID: mainBingo){(name, message) in
            return
        }
        XCTAssertNil(stateless.statefulLambda)
        XCTAssertNil(stateless.state)
        XCTAssertEqual(stateless.queue, DispatchQueue.main)
        XCTAssertEqual(stateless.registeredPid, mainBingo)
        XCTAssertNotNil(stateless.statelessLambda)
        XCTAssertNoThrow(stateless.statelessLambda!(mainBingo,3))
    }
    
    func testStatefulSwerlProcessWithDefaults() throws {
        let hasState = Pid(id: 0, serial: 1, creation: 0)
        let stateful:SwErlProcess = try! SwErlProcess(registrationID: hasState,initialState: ["eggs","flour"]){(procName, message ,state) in
            var updatedState:[String] = state as![String]
            updatedState.append(message as! String)
            return (true,updatedState)
        }
        XCTAssertNil(stateful.statelessLambda)
        XCTAssertNotNil(stateful.state)
         XCTAssertTrue(["eggs","flour"] == stateful.state as! [String])
        XCTAssertEqual(stateful.queue, statefulProcessDispatchQueue)
        XCTAssertEqual(stateful.registeredPid, hasState)
        XCTAssertNotNil(stateful.statefulLambda)
        XCTAssertTrue(stateful.statefulLambda!(hasState,"butter",["salt","water"]) as!(Bool,[String]) == (true,["salt","water","butter"]))
    }
    
    func testStatefulSwerlProcessNoDefaults() throws {
        let hasState = Pid(id: 0, serial: 1, creation: 0)
        let stateful:SwErlProcess = try! SwErlProcess(queueToUse:DispatchQueue.main,registrationID: hasState,initialState: ["eggs","flour"]){(procName, message ,state) in
                var updatedState:[String] = state as![String]
                updatedState.append(message as! String)
                return (true,updatedState)
            }
        XCTAssertNil(stateful.statelessLambda)
        XCTAssertNotNil(stateful.state)
         XCTAssertTrue(["eggs","flour"] == stateful.state as! [String])
        XCTAssertEqual(stateful.queue, DispatchQueue.main)
        XCTAssertEqual(stateful.registeredPid, hasState)
        XCTAssertNotNil(stateful.statefulLambda)
        XCTAssertTrue(stateful.statefulLambda!(hasState,"butter",["salt","water"]) as!(Bool,[String]) == (true,["salt","water","butter"]))
    }
    
    func testSwErlRegistry() throws{
        let first = Pid(id: 0, serial: 1, creation: 0)
        let second = Pid(id: 0, serial: 2, creation: 0)
        let third = Pid(id: 0, serial: 3, creation: 0)
        XCTAssertEqual(Registrar.instance.processesLinkedToPid.count, 0)
        let firstProc = try SwErlProcess(registrationID: first){(procName, message) in
            return
        }
        let secondProc = try SwErlProcess(registrationID: second){(procName, message) in
            return
        }
        let thirdProc = try SwErlProcess(registrationID: third){(procName, message) in
            return
        }
        XCTAssertNil(Registrar.instance.processesLinkedToPid[first])
        XCTAssertNil(Registrar.instance.processesLinkedToPid[second])
        XCTAssertNil(Registrar.instance.processesLinkedToPid[third])
        
        XCTAssertNoThrow(try Registrar.link(firstProc, PID: first))
        XCTAssertNoThrow(try Registrar.link(secondProc, PID: second))
        XCTAssertNoThrow(try Registrar.link(thirdProc, PID: third))
        
        
        XCTAssertNotNil(Registrar.instance.processesLinkedToPid[first])
        XCTAssertNotNil(Registrar.instance.processesLinkedToPid[second])
        XCTAssertNotNil(Registrar.instance.processesLinkedToPid[third])
        XCTAssertEqual(3, Registrar.instance.processesLinkedToPid.count)
        
        
        XCTAssertThrowsError(try Registrar.link(thirdProc, PID: third))
        
        XCTAssertTrue(Registrar.getAllPIDs().contains(first))
        XCTAssertTrue(Registrar.getAllPIDs().contains(second))
        XCTAssertTrue(Registrar.getAllPIDs().contains(third))
        XCTAssertFalse(Registrar.getAllPIDs().contains(Pid(id: 0, serial: 0, creation: 0)))
        
        XCTAssertNotNil(Registrar.getProcess(forID: second))
        XCTAssertNil(Registrar.getProcess(forID: Pid(id: 0, serial: 0, creation: 0)))
        
        XCTAssertNoThrow(Registrar.unlink(second))
        XCTAssertNil(Registrar.getProcess(forID: second))
        XCTAssertEqual(2, Registrar.getAllPIDs().count)
        
    }
    func testSequencingOfStatefulProcesses()throws{
        
        let pid = try spawn(initialState: ""){(procID,state,message) in
            Thread.sleep(forTimeInterval: message as! Double)
            guard let state = state as? String else{
                return ""
            }
            if state == ""{
                return "\(message as! Double)"
            }
            return "\(state),\(message as! Double)"
        }
        pid ! 5.0
        pid ! 2.0
        pid ! 0.0
        

        XCTAssertEqual("5.0,2.0,0.0", Registrar.getProcess(forID: pid)?.state as! String)
    }
    
    
    
    @available(macOS 13.0, *)
    func testSizeAndSpeed() throws{
        
        print("\n\n\n!!!!!!!!!!!!!!!!!!! \nsize of SwErlProcess: \(MemoryLayout<SwErlProcess>.size ) bytes")
        
        let stateless = {@Sendable(procName:Pid, message:Any) in
            return
        }
        let stateful = {@Sendable (pid:Pid,state:Any,message:Any)->Any in
            return 7
        }
        let timer = ContinuousClock()
        let count:Int64 = 1000000
        var time = try timer.measure{
            for _ in 0..<count{
                _ = try spawn(function: stateless)
            }
        }
        print("stateless spawning took \(time.components.attoseconds/count) attoseconds per instantiation")
        
        time = try timer.measure{
            for _ in 0..<count{
                _ = try spawn(initialState: 7, function: stateful)
            }
        }
        print("stateful spawning took \(time.components.attoseconds/count) attoseconds per instantiation\n!!!!!!!!!!!!!!!!!!!\n\n\n")
        Registrar.instance.processesLinkedToPid = [:]//clear the million registered processes
        print("!!!!!!!!!!!!!!!!!!! \n Sending \(count) messages to stateful process")
        var Pid = try spawn(initialState: 7, function: stateful)
        time = timer.measure{
            for _ in 0..<count{
                Pid ! 3
            }
        }
        print(" Stateful message passing took \(time.components.attoseconds/count) attoseconds per message sent\n!!!!!!!!!!!!!!!!!!!\n\n\n")
        
        print("!!!!!!!!!!!!!!!!!!! \n Sending \(count) messages to stateless process")
        Pid = try spawn(function: stateless)
        time = timer.measure{
            for _ in 0..<count{
                Pid ! 3
            }
        }
        print(" Stateless message passing took \(time.components.attoseconds/count) attoseconds per message sent\n!!!!!!!!!!!!!!!!!!!\n\n\n")
        time = timer.measure{
            for _ in 0..<count{
                Task {
                    await duplicateStatelessProcessBehavior(message:"hello")
                }
            }
        }
        print("Async/await in Tasks took \(time.components.attoseconds/count) attoseconds per task started\n!!!!!!!!!!!!!!!!!!!\n\n\n")
        time = timer.measure{
            for _ in 0..<count{
                DispatchQueue.global().async {
                    self.doNothing()
                    
                }
            }
        }
        print("Using dispatch queue only took \(time.components.attoseconds/count) attoseconds per call started\n!!!!!!!!!!!!!!!!!!!\n\n\n")
        
    }
    
    func duplicateStatelessProcessBehavior(message:String) async{
        return
    }
    func doNothing(){
        return
    }

}
