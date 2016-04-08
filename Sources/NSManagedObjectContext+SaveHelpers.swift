//
//  NSManagedObjectContext+Extensions.swift
//  CoreDataSMS
//
//  Created by Robert Edwards on 2/23/15.
//  Copyright (c) 2015 Big Nerd Ranch. All rights reserved.
//

import CoreData

public typealias CoreDataStackSaveCompletion = CoreDataStack.SaveResult -> Void

/**
 Convenience extension to `NSManagedObjectContext` that ensures that saves to contexts of type
 `MainQueueConcurrencyType` and `PrivateQueueConcurrencyType` are dispatched on the correct GCD queue.
*/
public extension NSManagedObjectContext {

    /**
    Convenience method to synchronously save the `NSManagedObjectContext` if changes are present.
    Method also ensures that the save is executed on the correct queue when using Main/Private queue concurrency types.
     
     - throws: Errors produced by the `save()` function on the `NSManagedObjectContext`
    */
    public func saveContextAndWait() throws {
        switch concurrencyType {
        case .ConfinementConcurrencyType:
            try sharedSaveFlow()
        case .MainQueueConcurrencyType,
             .PrivateQueueConcurrencyType:
            try performAndWaitOrThrow(sharedSaveFlow)
        }
    }

    /**
    Convenience method to asynchronously save the `NSManagedObjectContext` if changes are present.
    Method also ensures that the save is executed on the correct queue when using Main/Private queue concurrency types.

    - parameter completion: Completion closure with a `SaveResult` to be executed upon the completion of the save operation.
    */
    public func saveContext(completion: CoreDataStackSaveCompletion? = nil) {
        func saveFlow() {
            do {
                try sharedSaveFlow()
                completion?(.Success)
            } catch let saveError {
                completion?(.Failure(saveError))
            }
        }

        switch concurrencyType {
        case .ConfinementConcurrencyType:
            saveFlow()
        case .PrivateQueueConcurrencyType,
        .MainQueueConcurrencyType:
            performBlock(saveFlow)
        }
    }

    private func sharedSaveFlow() throws {
        guard hasChanges else {
            return
        }

        try save()
    }
    
    /**
     Convenience method to synchronously save the `NSManagedObjectContext` if changes are present.
     If `save()` function on the `NSManagedObjectContext` produces error, all changes will be rolled back and the error thrown.
     
     - throws: Errors produced by the `save()` function on the `NSManagedObjectContext`
     */
    public func saveOrRollback() throws {
        do {
            try saveContextAndWait()
        } catch {
            rollback()
            throw error
        }
    }
    
    /**
     Convenience method to asynchronously save the `NSManagedObjectContext` if changes are present.
     The method uses dispatch group to group multiple calls. Save will be delayed, so multiple calls to this method won't cause it 
     untill maximum changed objects count will be exceeded. Save or rollback will be always performed on context's queue.
     If `save()` function on the `NSManagedObjectContext` produces error, all changes will be rolled back and the error thrown.
     
     - parameter group: `dispatch_group_t` that will be used group calls to this method.
     - parameter maxChangedObjectsCount: Maximum changed objects count, that if exceeded will cause save.
     - parameter onError: A closure that will be called when `save()` function on the `NSManagedObjectContext` produces error.
     */
    public func saveOrRollbackWithGroup(group: dispatch_group_t, maxChangedObjectsCount: Int = 100, onError: (ErrorType) -> ()) {
        guard changedObjectsCount < maxChangedObjectsCount else {
            do { try saveOrRollback() }
            catch { onError(error) }
            return
        }
        let queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)
        dispatch_group_notify(group, queue) {
            dispatch_group_enter(group)
            self.performBlock {
                guard self.hasChanges else { return }
                do { try self.saveOrRollback() }
                catch { onError(error) }
                dispatch_group_leave(group)
            }
        }
    }
    
    private var changedObjectsCount: Int {
        return insertedObjects.count + updatedObjects.count + deletedObjects.count
    }
}
