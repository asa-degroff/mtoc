# Album Art Extraction and Management Plan

## Overall Architecture

### 1. **Extraction Strategy**
- Use TagLib to extract embedded artwork from audio files during the initial library scan
- Handle multiple image types (JPEG, PNG, etc.) and convert to a standardized format
- Extract only once per album (not per track) to avoid redundancy
- Fall back to looking for common image files in the album folder (cover.jpg, folder.jpg, album.jpg, front.jpg)

### 2. **Storage Approach**
I'd recommend a **hybrid storage model**:
- **Thumbnails**: Store in SQLite as BLOBs for fast access
- **Full-size images**: Store on filesystem with paths in database
  
This gives you the best of both worlds - quick database queries for thumbnails during browsing, and efficient filesystem storage for large images.

### 3. **Thumbnail Sizes**
Create multiple thumbnail sizes for different UI contexts:
- **Grid view**: 128x128 or 150x150
- **Now playing**: Full size (capped at reasonable maximum, maybe 1800x1800)

### 4. **Database Schema**
```sql
album_art (
    id INTEGER PRIMARY KEY,
    album_id INTEGER,
    full_path TEXT,           -- filesystem path to full image
    full_hash TEXT,           -- MD5/SHA1 for deduplication
    thumbnail BLOB,           -- 150x150
    width INTEGER,
    height INTEGER,
    format TEXT,
    file_size INTEGER,
    extracted_date TIMESTAMP
)
```

### 5. **Processing Pipeline**
1. **During library scan**:
   - Extract artwork using TagLib
   - Check hash for duplicates
   - Resize to create thumbnails using Qt's image scaling
   - Store thumbnails in DB, full image on disk
   
2. **Lazy loading**:
   - Load thumbnails directly from DB for browsing
   - Load full images from disk only when needed

### 6. **Performance Optimizations**
- **Deduplication**: Use image hashing to avoid storing duplicate album art
- **Async processing**: Extract/resize in background threads
- **Batch operations**: Process multiple albums in transactions
- **Memory management**: Use QPixmapCache for recently viewed images
- **Progressive loading**: Show thumbnail immediately, load full image in background

### 7. **Fallback Strategy**
Priority order for finding album art:
1. Embedded in audio file
2. Image files in same directory (cover.*, folder.*, album.*, front.*)
3. Generic placeholder

### 8. **Format Considerations**
- Store thumbnails as AVIF for size efficiency
- Keep original format for full images when possible

### 9. **Cache Management**
- Implement cache eviction for full-size images
- Keep all thumbnails in memory/DB