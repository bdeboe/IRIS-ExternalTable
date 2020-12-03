Class Stream.BufferedLineReader Extends %RegisteredObject [ Abstract ]
{

/// default length (in bytes) to fetch from the remote file
Parameter RANGESIZE As INTEGER = 1048576;

/// how many ranges of <parameter>RANGESIZE</parameter> can be cached
Parameter CACHESIZE As INTEGER = 5;

Property Location As %String;

Property AtEnd As %Boolean [ InitialExpression = 0 ];

Property CurrentLineNumber As %Integer;

Property FileCount As %Integer [ InitialExpression = 1 ];

/// Cache of streams, indexed by offsetStart
/// ..StreamCache(fileNumber, offsetStart) = [%Stream.TmpCharacter]
/// ..StreamCache(fileNumber, offsetStart, "currentLine") = currentLine
/// ..StreamCache(fileNumber, offsetStart, "last") = [FetchRange did not return as much data as we expected]
Property StreamCache [ Internal, MultiDimensional ];

/// ..LineIndex(lineNumber) = $lb(fileNumber, offsetStart, lastCompleteLineNumber, lengthIncludingLastLine)
Property LineIndex [ Internal, MultiDimensional ];

/// List of cache entries most recently used (expressed as "fileNumber:offsetStart")
/// Length should be <parameter>CACHESIZE</parameter> or less
Property LRU As %List [ Internal, Private ];

Method ClearCache() As %Status
{
	kill ..LineIndex, ..StreamCache
	set ..LRU = ""
	quit $$$OK
}

/// Returns the line at the specified number and advances <property>CurrentLineNumber</property> to that line
/// (reading at <property>CurrentLineNumber</property>+1 when <var>lineNumber</var><=0)
/// If this line is not in a cached stream, fetch the next range until we find it
Method ReadLine(lineNumber As %Integer = 0, Output sc As %Status) As %String
{
	set sc = $$$OK, returnLine = "", ..AtEnd = 0
	try {
		
		set:lineNumber<=0 lineNumber = i%CurrentLineNumber+1
		
		// check if we already have this lineNumber in the known ranges
check	set rangeFirstLine = $order(..LineIndex(lineNumber+1), -1, rangeData)
		
		if rangeFirstLine="" {
			// still need to fetch the very first range of the very first file
			set sc = ..FetchRange(1, 0)
			quit:$$$ISERR(sc)
			
			// now check again
			goto check
		}
		
		// get the starting offset of this range
		set fileNumber = $lg(rangeData, 1), rangeOffset = $lg(rangeData,2)
		
		// rangeData now has the last known range before the requested line number
		// and possibly including it
		if $ld(rangeData,3,lastCompleteLineNumber) {
			
			// if we know the last complete line number for this range, we can check if it
			// includes the requested one
			if (lineNumber > lastCompleteLineNumber) {
				
				// we know it's not in this range, but the previous range was the last one we
				// read, so we'll need to fetch the next stream or file and check again. 
				if $lg(rangeData,5) { 
					if (fileNumber = ..FileCount) {
						// the user requested something past the end
						quit 
					}
					// move to the next file
					set sc = ..FetchRange(fileNumber+1, 0,, lastCompleteLineNumber+1)
					quit:$$$ISERR(sc)
				} else {
					// still in the same file
					set newOffset = rangeOffset + $lg(rangeData,4)
					set sc = ..FetchRange(fileNumber, newOffset,, lastCompleteLineNumber+1)
					quit:$$$ISERR(sc)
				}
				goto check
				
			} else {
				
				// we know the line is in this range, so let's proceed
				goto seek
				
			}
			
		} else {
			
			// we don't know whether the requested line is in this range, but it's the last
			// known one preceding it, so we can only start scanning
			goto seek
		}

seek	// check if the range is still cached
		#dim cachedStream as %Stream.TmpCharacter
		if '$d(..StreamCache(fileNumber, rangeOffset),cachedStream) {
			// this one got removed from the cache, so we'll need to fetch it again,
			// but this time we know the exact range
			set sc = ..FetchRange(fileNumber, rangeOffset, rangeOffset + $lg(rangeData,4), rangeFirstLine)
			quit:$$$ISERR(sc)
			set cachedStream = ..StreamCache(fileNumber, rangeOffset)
		}
		set currentLine = $g(..StreamCache(fileNumber, rangeOffset,"currentLine"))
		
		// update LRU list
		set lruPos = $lf(..LRU,fileNumber_":"_rangeOffset)
		if lruPos'=1 {
			set ..LRU = $lb(fileNumber_":"_rangeOffset)_$li(..LRU,1,lruPos-1)_$li(..LRU,lruPos+1,*)
		}
		
		if currentLine >= lineNumber {
			// we've already read past the requested line in this stream, so rewind
			set sc = cachedStream.Rewind()
			quit:$$$ISERR(sc)
			set currentLine = rangeFirstLine-1
		}
		
		// advance
		while currentLine < lineNumber {
			set line = cachedStream.ReadLine(),
				currentLine = currentLine + 1
			
			if cachedStream.AtEnd {
				
				// if this was a previously cached stream, it's simply the last one and we know it's complete
				if $lg(rangeData,3) {
					quit
				}
				
				// TODO: if this was the first line we tried to read, we may have to fetch a larger chunk
				/* if (currentLine = rangeFirstLine) {
					set sc = $$$ERROR($$$GeneralError, "This line is too long!")
					quit
				}*/
				
				
				// this means we may only have a partial line, so close off this range
				// and go back to look for the next one, just to be sure
				
				// if this is the last stream of this file, use the row
				if $g(..StreamCache(fileNumber, rangeOffset, "last")) {
					
					// update LineIndex.
					// The flag at the end means this was the last stream of this file
					set ..LineIndex(rangeFirstLine) = $lb(fileNumber, rangeOffset, currentLine, cachedStream.Size, 1)
					set ..AtEnd = (fileNumber = ..FileCount)
					quit
					
				} else {
					
					// update LineIndex and try the next stream for this file
					set ..LineIndex(rangeFirstLine) = $lb(fileNumber, rangeOffset, currentLine-1, cachedStream.Size - $l(line))
					goto check
					
				}
			}
		}
		quit:$$$ISERR(sc)
		
		
		set ..StreamCache(fileNumber, rangeOffset, "currentLine") = currentLine
		
		// at this point, either currentLine < lineNumber because we're at the very end,
		// or currentLine = lineNumber, yay!
		if (currentLine = lineNumber) {
			set returnLine = line
		}
		
		// advance current line number
		set i%CurrentLineNumber = lineNumber
		
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	quit returnLine
}

Method FetchRange(fileNumber As %Integer, offsetStart As %Integer, offsetEnd As %Integer = -1, firstLine As %Integer = 1) As %Status
{
	set sc = $$$OK
	try {
		if offsetEnd <= 0 {
			set offsetEnd = offsetStart + ..#RANGESIZE
		}
		
		set sc = ..FetchRangeStream(fileNumber, offsetStart, offsetEnd, .stream)
		quit:$$$ISERR(sc)
		
		set ..StreamCache(fileNumber, offsetStart) = stream,
			..StreamCache(fileNumber, offsetStart, "currentLine") = firstLine-1,
			..StreamCache(fileNumber, offsetStart, "last") = (stream.Size < (offsetEnd-offsetStart)),
			..LRU = $lb(fileNumber_":"_offsetStart)_..LRU
			
		// only update the index if we didn't know more about it already
		set:'$d(..LineIndex(firstLine)) ..LineIndex(firstLine) = $lb(fileNumber, offsetStart)
		
		// check if a stream needs to be evicted from cache
		if $ll(..LRU)>..#CACHESIZE {
			set evict = $li(..LRU,*), 
				..LRU=$li(..LRU,1,..#CACHESIZE)
			kill ..StreamCache($p(evict,":",1),$p(evict,":",2))
		}
		
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	return sc
}

Method FetchRangeStream(fileNumber As %Integer, offsetStart As %Integer, offsetEnd As %Integer, Output stream As %Stream.Object) As %Status [ Abstract ]
{
	set sc = $$$OK
	try {
		
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	return sc
}

}
