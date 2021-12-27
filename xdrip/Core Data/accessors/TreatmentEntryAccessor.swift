//
//  TreatmentEntryAccessor.swift
//  xdrip
//
//  Created by Eduardo Pietre on 24/12/21.
//  Copyright © 2021 Johan Degraeve. All rights reserved.
//

import Foundation
import CoreData
import os


class TreatmentEntryAccessor {
	
	// MARK: - Properties
	
	/// for logging
	private var log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryApplicationDataTreatments)
	
	/// CoreDataManager to use
	private let coreDataManager:CoreDataManager
	
	// MARK: - initializer
	
	init(coreDataManager:CoreDataManager) {
		self.coreDataManager = coreDataManager
	}
	
	// MARK: - public functions
	
	/// Gives the 50 latest treatments
	///
	/// - returns: an array with treatments, can be empty array.
	///     Order by timestamp, descending meaning the treatment at index 0 is the youngest
	func getLatestTreatments() -> [TreatmentEntry] {
		return getLatestTreatments(limit:50)
	}
	
	/// Returns the treatments among the 50 latest
	/// that have not yet been uploaded
	///
	/// - returns: an array with treatments not uploaded, can be empty array.
	///     Order by timestamp, descending meaning the treatment at index 0 is the youngest
	func getRequireUploadTreatments() -> [TreatmentEntry] {
		// filter by not uploaded
		return getLatestTreatments().filter { treatment in
			return !treatment.uploaded
		}
	}
	
	/// Gives latest treatments
	///
	/// - parameters:
	///     - limit : maximum amount of treatments to return, if nil then no limit in amount
	/// - returns: an array with treatments, can be empty array.
	///     Order by timestamp, descending meaning the treatment at index 0 is the youngest
	func getLatestTreatments(limit:Int) -> [TreatmentEntry] {
		return getLatestTreatments(limit:limit, howOld:nil)
	}
	
	/// Gives treatments with maximumDays old
	///
	/// - parameters:
	///     - limit : maximum amount of treatments to return, if nil then no limit in amount
	///     - howOld : maximum age in days, it will calculate exacte (24 hours) * howOld, if nil then no limit in age
	/// - returns: an array with treatments, can be empty array.
	///     Order by timestamp, descending meaning the treatment at index 0 is the youngest
	func getLatestTreatments(limit:Int?, howOld:Int?) -> [TreatmentEntry] {
		
		// if maximum age specified then create fromdate
		var fromDate:Date?
		if let howOld = howOld, howOld >= 0 {
			fromDate = Date(timeIntervalSinceNow: Double(-howOld * 60 * 60 * 24))
		}
		
		return getLatestTreatments(limit: limit, fromDate: fromDate)
	}
	
	/// Gives treatments with timestamp higher than fromDate
	///
	/// - parameters:
	///     - limit : maximum amount of treatments to return, if nil then no limit in amount
	///     - fromDate : treatment must have date > fromDate
	/// - returns: an array with treatments, can be empty array.
	///     Order by timestamp, descending meaning the treatment at index 0 is the youngest
   func getLatestTreatments(limit:Int?, fromDate:Date?) -> [TreatmentEntry] {
		
		var returnValue:[TreatmentEntry] = []
				
		let treatments = fetchTreatments(limit: limit, fromDate: fromDate)
		
		loop: for (_, treatment) in treatments.enumerated() {
			returnValue.append(treatment)
		}
		
		return returnValue
	}
	
	/// gets last treatment
	func last() -> TreatmentEntry? {
		let treatments = getLatestTreatments(limit: 1, howOld: nil)
		if treatments.count > 0 {
			return treatments.last
		} else {
			return nil
		}
	}
	
	/// gets treatments, synchronously, in the managedObjectContext's thread
	/// - returns:
	///        treatments sorted by timestamp, ascending (ie first is oldest)
	/// - parameters:
	///     - to : if specified, only return treatments with timestamp  smaller than fromDate (not equal to)
	///     - from : if specified, only return treatments with timestamp greater than fromDate (not equal to)
	///     - managedObjectContext : the ManagedObjectContext to use
	func getTreatments(from: Date?, to: Date?, on managedObjectContext: NSManagedObjectContext) -> [TreatmentEntry] {
		
		let fetchRequest: NSFetchRequest<TreatmentEntry> = TreatmentEntry.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(TreatmentEntry.date), ascending: true)]
		
		// create predicate
		if let from = from, to == nil {
			let predicate = NSPredicate(format: "date > %@", from as NSDate)
			fetchRequest.predicate = predicate
		} else if let to = to, from == nil {
			let predicate = NSPredicate(format: "date < %@", to as NSDate)
			fetchRequest.predicate = predicate
		} else if let to = to, let from = from {
			let predicate = NSPredicate(format: "date < %@ AND date > %@", to as CVarArg, from as NSDate)
			fetchRequest.predicate = predicate
		}
		
		var treatments: [TreatmentEntry] = []
		
		managedObjectContext.performAndWait {
			do {
				// Execute Fetch Request
				treatments = try fetchRequest.execute()
			} catch {
				let fetchError = error as NSError
				trace("in getTreatments, Unable to Execute BgReading Fetch Request : %{public}@", log: self.log, category: ConstantsLog.categoryApplicationDataTreatments, type: .error, fetchError.localizedDescription)
			}
		}
		
		return treatments
	}
	
	/// deletes treatmentEntry, synchronously, in the managedObjectContext's thread
	///     - treatmentEntry : treatmentEntry to delete
	///     - managedObjectContext : the ManagedObjectContext to use
	func delete(treatmentEntry: TreatmentEntry, on managedObjectContext: NSManagedObjectContext) {
		
		managedObjectContext.performAndWait {
			
			managedObjectContext.delete(treatmentEntry)
			
			// save changes to coredata
			do {
				try managedObjectContext.save()
			} catch {
				trace("in delete bgReading,  Unable to Save Changes, error.localizedDescription  = %{public}@", log: self.log, category: ConstantsLog.categoryApplicationDataTreatments, type: .error, error.localizedDescription)
			}
		}
	}
	
	// MARK: - private helper functions
	
	/// returnvalue can be empty array
	/// - parameters:
	///     - limit: maximum amount of treatments to fetch, if 0 then no limit
	///     - fromDate : if specified, only return readings with timestamp > fromDate
	/// - returns:
	///     List of treatments, descending, ie first is youngest
	private func fetchTreatments(limit:Int?, fromDate:Date?) -> [TreatmentEntry] {
		let fetchRequest: NSFetchRequest<TreatmentEntry> = TreatmentEntry.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(TreatmentEntry.date), ascending: false)]
		
		// if fromDate specified then create predicate
		if let fromDate = fromDate {
			let predicate = NSPredicate(format: "date > %@", fromDate as NSDate)
			fetchRequest.predicate = predicate
		}
		
		// set fetchLimit
		if let limit = limit, limit >= 0 {
			fetchRequest.fetchLimit = limit
		}
		
		var treatments: [TreatmentEntry] = []
		
		coreDataManager.mainManagedObjectContext.performAndWait {
			do {
				// Execute Fetch Request
				treatments = try fetchRequest.execute()
			} catch {
				let fetchError = error as NSError
				trace("in fetchTreatments, Unable to Execute BgReading Fetch Request : %{public}@", log: self.log, category: ConstantsLog.categoryApplicationDataTreatments, type: .error, fetchError.localizedDescription)
			}
		}
		
		return treatments
	}
	
}
