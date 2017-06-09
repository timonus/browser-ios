/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

public typealias Timestamp = UInt64
public typealias MicrosecondTimestamp = UInt64

public let ThreeWeeksInSeconds = 3 * 7 * 24 * 60 * 60

public let OneMonthInMilliseconds = 30 * OneDayInMilliseconds
public let OneWeekInMilliseconds = 7 * OneDayInMilliseconds
public let OneDayInMilliseconds = 24 * OneHourInMilliseconds
public let OneHourInMilliseconds = 60 * OneMinuteInMilliseconds
public let OneMinuteInMilliseconds = 60 * OneSecondInMilliseconds
public let OneSecondInMilliseconds: UInt64 = 1000

extension NSDate {
    public class func now() -> Timestamp {
        return UInt64(1000 * NSDate().timeIntervalSince1970)
    }

    public class func nowNumber() -> NSNumber {
        return NSNumber(unsignedLongLong: now())
    }

    public class func nowMicroseconds() -> MicrosecondTimestamp {
        return UInt64(1000000 * NSDate().timeIntervalSince1970)
    }
    
    public func toTimestamp() -> Timestamp {
        return UInt64(self.timeIntervalSince1970 * 1000)
    }
    
    public func toMicrosecondTimestamp() -> MicrosecondTimestamp {
        return self.toTimestamp() * 1000
    }

    public class func fromTimestamp(timestamp: Timestamp) -> NSDate {
        return NSDate(timeIntervalSince1970: Double(timestamp) / 1000)
    }

    public class func fromMicrosecondTimestamp(microsecondTimestamp: MicrosecondTimestamp) -> NSDate {
        return NSDate(timeIntervalSince1970: Double(microsecondTimestamp) / 1000000)
    }

    public func toRelativeTimeString() -> String {
        let now = NSDate()

        let units: NSCalendarUnit = [NSCalendarUnit.Second, NSCalendarUnit.Minute, NSCalendarUnit.Day, NSCalendarUnit.WeekOfYear, NSCalendarUnit.Month, NSCalendarUnit.Year, NSCalendarUnit.Hour]

        let components = NSCalendar.currentCalendar().components(units,
            fromDate: self,
            toDate: now,
            options: [])
        
        if components.year > 0 {
            return String(format: NSDateFormatter.localizedStringFromDate(self, dateStyle: NSDateFormatterStyle.ShortStyle, timeStyle: NSDateFormatterStyle.ShortStyle))
        }

        if components.month == 1 {
            return Strings.More_than_a_month
        }

        if components.month > 1 {
            return String(format: NSDateFormatter.localizedStringFromDate(self, dateStyle: NSDateFormatterStyle.ShortStyle, timeStyle: NSDateFormatterStyle.ShortStyle))
        }

        if components.weekOfYear > 0 {
            return Strings.More_than_a_week
        }

        if components.day == 1 {
            return Strings.Yesterday
        }

        if components.day > 1 {
            return String(format: Strings.This_week, String(components.day))
        }

        if components.hour > 0 || components.minute > 0 {
            let absoluteTime = NSDateFormatter.localizedStringFromDate(self, dateStyle: NSDateFormatterStyle.NoStyle, timeStyle: NSDateFormatterStyle.ShortStyle)
            return String(format: Strings.Today_at_template, absoluteTime)
        }

        return Strings.Just_now
    }
}

public func decimalSecondsStringToTimestamp(input: String) -> Timestamp? {
    var double = 0.0
    if NSScanner(string: input).scanDouble(&double) {
        return Timestamp(double * 1000)
    }
    return nil
}

public func millisecondsToDecimalSeconds(input: Timestamp) -> String {
    let val: Double = Double(input) / 1000
    return String(format: "%.2F", val)
}
