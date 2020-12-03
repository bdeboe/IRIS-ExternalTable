Class Stream.BufferedLineReaderLocal Extends BufferedLineReader [ Language = objectscript ]
{

/// Dummy size for testing
Parameter RANGESIZE = 1000;

Property FileList As %List [ Internal, Private ];

Property CurrentFile As %Integer [ Internal, Private ];

Property File As %Stream.FileCharacter [ Internal, Private ];

Method %OnNew(locations As %List) As %Status [ Internal, ServerOnly = 1 ]
{
	set:'$lv(locations) locations = $lb(locations)
	set ..FileList = locations, 
		..CurrentFile = 1, 
		..FileCount = $ll(locations)
	set ..File = ##class(%Stream.FileCharacter).%New()
	quit ..File.LinkToFile($li(locations,1))
}

Method FetchRangeStream(fileNumber As %Integer, offsetStart As %Integer, offsetEnd As %Integer, Output stream As %Stream.Object) As %Status
{
	set sc = $$$OK
	try {
		if fileNumber'=..CurrentFile {
			set sc = ..File.LinkToFile($li(..FileList,fileNumber))
			quit:$$$ISERR(sc)
			set ..CurrentFile = fileNumber
		}
		
		set stream = ##class(%Stream.TmpCharacter).%New()
		set sc = ..File.MoveTo(offsetStart+1) // 1-based
		quit:$$$ISERR(sc)
		set len = (offsetEnd-offsetStart)
		do stream.Write(..File.Read(.len))
		quit:$$$ISERR(sc)
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	return sc
}

}
