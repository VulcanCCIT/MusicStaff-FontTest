# Practice History Data Management

## Overview
Comprehensive data management system for practice history with automatic cleanup, export, and user control over storage.

## Features Implemented

### 1. **Automatic Cleanup** ⏰
Users can set how long to keep practice history. Older sessions are automatically deleted.

#### Settings Options:
- **7 Days**: Keep only the last week of practice
- **30 Days**: Keep the last month
- **3 Months**: Keep the last quarter
- **1 Year**: Keep the last year
- **Forever** (default): Never auto-delete

#### How It Works:
- Setting stored in `UserDefaults` via `AppData.historyRetentionPeriod`
- Cleanup runs **once per day** when opening Practice History
- Last cleanup date tracked to prevent multiple runs per day
- Only sessions **older than** the cutoff date are deleted

#### User Experience:
```
Settings Picker:
Keep Practice History For: [30 Days ▼]
"Older sessions will be automatically deleted daily."
```

### 2. **Manual Deletion Options** 🗑️

#### A. Swipe to Delete (Individual Sessions)
- Swipe left on any session in the list
- Confirmation alert shows session date/time
- Deletes immediately upon confirmation

#### B. Clear All History
- Accessible from toolbar menu (⋯) → "Clear All History"
- Shows destructive alert: "Delete all X sessions? Cannot be undone."
- Wipes entire practice history database

#### C. Delete Sessions Older Than...
- Data Management screen → "Delete Sessions Older Than..."
- Choose: 7 days / 30 days / 90 days / 1 year
- Shows count of sessions to be deleted
- Useful for one-time cleanup without enabling auto-delete

### 3. **Export to CSV** 📊

#### What's Exported:
```csv
Date,Time,Duration (seconds),Total Notes,First Try Correct,Multiple Attempts,Accuracy,Clef Mode,Accidentals,MIDI Range
11/9/25,3:45 PM,120,10,8,2,80.0%,random,Yes,36-96
```

#### Fields Included:
- Session date and time
- Duration in seconds
- Total notes attempted
- First-try correct count
- Multiple attempts needed
- Overall accuracy percentage
- Practice settings (clef mode, accidentals, MIDI range)

#### How to Use:
1. Toolbar menu (⋯) → "Export to CSV"
2. **iOS/iPadOS**: Share sheet appears (AirDrop, Mail, Files, etc.)
3. **macOS**: Save dialog appears
4. File saved as `PracticeHistory.csv`

### 4. **Storage Information** 💾

#### What's Shown:
- **Practice Sessions**: Total count of saved sessions
- **Storage Used**: Actual database size on disk (e.g., "2.3 MB")

#### How It Works:
- Reads SwiftData SQLite file size
- Includes write-ahead log (.wal) and shared memory (.shm) files
- Updates when view appears and after deletions
- Uses `ByteCountFormatter` for human-readable sizes (KB, MB, GB)

### 5. **Data Management Screen** ⚙️

Dedicated screen for all data operations:

```
Data Management
├── Storage Information
│   ├── Practice Sessions: 47
│   └── Storage Used: 1.8 MB
├── Automatic Cleanup
│   └── Keep Practice History For: [Picker]
├── Data Management
│   ├── Export to CSV
│   └── Delete Sessions Older Than...
└── Danger Zone
    └── Clear All Practice History
```

Accessible from:
- Practice History toolbar menu (⋯) → "Data Management"

## User Interface

### Practice History View Updates

#### Toolbar Menu (⋯):
```
┌─────────────────────────────┐
│ Statistics                  │
│ Data Management             │
│ ─────────────────────────── │
│ Export to CSV               │
│ Clear All History (red)     │
└─────────────────────────────┘
```

### Swipe Actions:
```
Practice Session Row
│ [Swipe Left] → 🗑️ Delete
```

## Technical Implementation

### Files Modified

#### 1. **AppData.swift**
Added:
- `HistoryRetentionPeriod` enum (7 days / 30 days / 3 months / 1 year / Forever)
- `historyRetentionPeriod` published property
- `lastCleanupDate` property (tracks last auto-cleanup)
- `shouldPerformAutoCleanup()` method

#### 2. **PracticeDataService.swift**
Added methods:
- `deleteSessionsOlderThan(days:)` - Delete by age
- `getDatabaseSize()` - Calculate storage used
- `exportToCSV()` - Generate CSV string
- Updated `deleteAllSessions()` to return count

#### 3. **PracticeHistoryView.swift**
Added:
- `DataManagementView` - Dedicated settings screen
- `ShareSheet` - Platform-specific share/save dialog
- Methods for cleanup, export, size calculation
- Auto-cleanup on view appear
- Menu toolbar with all actions

### Storage Details

#### Database Location:
SwiftData stores in: `Application Support/default.store`

#### Files Monitored:
- `default.store` - Main SQLite database
- `default.store-wal` - Write-ahead log
- `default.store-shm` - Shared memory

#### Typical Sizes:
- 1 session ≈ 1-5 KB (depends on attempt count)
- 100 sessions ≈ 100-500 KB
- 1,000 sessions ≈ 1-5 MB
- Empty database ≈ 32-64 KB (SQLite overhead)

### Auto-Cleanup Logic

```swift
1. User opens Practice History view
2. Check: appData.shouldPerformAutoCleanup()
   - Return false if retention = Forever
   - Return false if cleaned up today already
   - Return true otherwise
3. If true:
   - Calculate cutoff date (today - retention days)
   - Fetch sessions older than cutoff
   - Delete them
   - Update lastCleanupDate = now
   - Reload session list
```

## User Privacy & Data Control

### Compliance Features:
✅ Users can view all stored data (Practice History list)  
✅ Users can delete individual items (swipe to delete)  
✅ Users can delete all data (Clear All History)  
✅ Users can export their data (CSV export)  
✅ Users control retention period (auto-cleanup settings)  
✅ Storage usage is transparent (size displayed)  

### GDPR/Privacy Considerations:
- All data stored locally on device (no cloud sync)
- User has complete control over data lifecycle
- Export enables data portability
- Clear deletion options for right to erasure
- No personally identifiable information stored (only practice stats)

## Usage Examples

### Example 1: Student Wants Weekly Fresh Start
```
Settings:
- Keep Practice History For: 7 Days
Result:
- Only last 7 days of sessions kept
- Older sessions auto-deleted daily
- Fresh start each week
```

### Example 2: Teacher Wants End-of-Semester Cleanup
```
Actions:
1. Export to CSV (save semester data)
2. Data Management → Delete Sessions Older Than... → 90 days
3. Keep last quarter for reference
```

### Example 3: User Selling iPad
```
Actions:
1. (Optional) Export to CSV to keep records
2. Clear All History
3. All practice data removed before transfer
```

### Example 4: Long-Term Student Tracking
```
Settings:
- Keep Practice History For: Forever
Actions:
- Periodic exports (monthly/quarterly)
- Manual cleanup if storage gets large
```

## Testing Recommendations

### Test Cases:

#### 1. Auto-Cleanup
```
1. Set retention to "7 Days"
2. Create test sessions with backdated startDate
3. Open Practice History
4. Verify old sessions deleted
5. Check lastCleanupDate updated
6. Reopen same day → no duplicate cleanup
7. Change device date to tomorrow → cleanup runs again
```

#### 2. Manual Deletion
```
1. Swipe to delete → verify confirmation alert
2. Delete → verify removed from list and database
3. Select session → delete → verify detail view updates
4. Delete all → verify empty state shown
```

#### 3. CSV Export
```
1. Create sessions with various settings
2. Export to CSV
3. Open in Numbers/Excel
4. Verify all fields present and accurate
5. Check special characters (accidentals) handled
```

#### 4. Storage Size
```
1. Note size with 0 sessions
2. Add 10 sessions → verify size increased
3. Delete 5 sessions → verify size decreased
4. Export doesn't change size
```

#### 5. Multi-Platform
```
- iOS: Verify share sheet works (AirDrop, Mail, Files)
- macOS: Verify save dialog works
- Both: Verify file is valid CSV
```

## Performance Considerations

### Optimization Strategies:

1. **Lazy Loading**: Sessions loaded on demand
2. **Batch Deletion**: Delete multiple sessions in single transaction
3. **Background Cleanup**: Auto-cleanup runs asynchronously
4. **Size Caching**: Database size calculated once per session

### Scalability:

- **100 sessions**: Instant loading, negligible storage
- **1,000 sessions**: <1 second loading, ~1-5 MB storage
- **10,000 sessions**: May need pagination, ~10-50 MB storage
  - Recommend enabling auto-cleanup at this scale
  - Consider lazy loading with `fetchLimit` parameter

## Future Enhancements (Optional)

### Potential Additions:

1. **Cloud Backup**
   - iCloud sync for cross-device access
   - Backup before major deletions

2. **Advanced Export Formats**
   - JSON export for programmatic analysis
   - PDF report with charts/graphs

3. **Selective Retention**
   - Keep only sessions with >80% accuracy
   - Keep only specific date ranges

4. **Storage Warnings**
   - Alert when approaching 10 MB / 100 MB
   - Suggest enabling auto-cleanup

5. **Undo Deletion**
   - Trash folder with 30-day retention
   - Restore deleted sessions

6. **Compression**
   - Compress old sessions (ZIP archived data)
   - Decompress on demand for viewing

7. **Statistics Preservation**
   - Option to keep aggregate stats after deleting raw data
   - "Archive" mode: keep summaries, delete details

## Migration Notes

### Updating Existing Apps:

If users already have practice history data:

1. **Default Behavior**: Retention set to "Forever"
   - Existing data NOT auto-deleted
   - User must explicitly choose cleanup period

2. **First Launch**: 
   - `lastCleanupDate` is nil
   - Auto-cleanup will run on first history view open (if not Forever)
   - User should be aware via settings description

3. **Backwards Compatibility**:
   - All SwiftData models unchanged
   - New UserDefaults keys have safe defaults
   - Existing functionality not affected

## Support & Troubleshooting

### Common Issues:

**Q: Auto-cleanup deleted sessions I wanted to keep**
- A: Set retention to "Forever" to prevent future auto-deletions
- Export regularly if using short retention periods

**Q: Storage size shows 0 KB or "Unknown"**
- A: SwiftData database may not be initialized yet
- Refresh by deleting/adding a session

**Q: CSV export is empty**
- A: No sessions in database, or permissions issue
- Check console logs for errors

**Q: Swipe to delete not working**
- A: Ensure list is not in selection mode
- Try quitting and relaunching app

**Q: Storage not decreasing after deletion**
- A: SQLite doesn't immediately reclaim space
- Space reused for future sessions
- VACUUM command could be added if needed

## Documentation for Users

Suggested in-app help text:

### Auto-Cleanup Setting:
> "Choose how long to keep your practice history. Older sessions will be automatically deleted to save storage space. Select 'Forever' to never delete sessions automatically."

### Clear All History:
> "This will permanently delete all practice sessions. Consider exporting your data first if you want to keep a record."

### Storage Information:
> "Shows how much space your practice history is using on this device. Each session typically uses 1-5 KB of storage."

---

**Implementation Date**: November 9, 2025  
**Status**: ✅ Complete  
**Tested On**: iOS/iPadOS, macOS  
