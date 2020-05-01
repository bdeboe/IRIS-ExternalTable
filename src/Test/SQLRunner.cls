Class Test.SQLRunner [ Abstract ]
{

ClassMethod RunSQLFile(filename) As %Status
{
    set teststatus=$$$OK
    if '##class(%File).Exists($get(^ET.Config("LocalDir"))_filename) {
        write !,"ERROR: Can not find file:"_ $get(^ET.Config("LocalDir"))_filename
        write !,"Check SQL test file name and 'LocalDir' configuration"
        set sc=$$$ERROR($$$GeneralError,"ERROR: Can not find file:"_ $get(^ET.Config("LocalDir"))_filename_" Check  SQL test file name and 'LocalDir' configuration")
        set teststatus=$SYSTEM.Status.AppendStatus(teststatus,sc)
    }
	write !, "RUNNING SQL FILE: "_$get(^ET.Config("LocalDir"))_filename
    Set sqlfile=##class(%Stream.FileCharacter).%New()
	Set sc=sqlfile.LinkToFile($get(^ET.Config("LocalDir"))_filename)
	//Set sqlfile.LineTerminator=$char(10)
    set linenum=0
    kill sql
    while 'sqlfile.AtEnd {
        set line=sqlfile.ReadLine()
        set linenum=linenum+1
        if ($extract(line,0,3)=" --") {
            if $d(sql) {
                set sc=..ExecuteSQL(.sql,filename_" line: "_(linenum-sql))
                if $$$ISERR(sc) {
                    set teststatus=$SYSTEM.Status.AppendStatus(teststatus,sc)
                }
            }
            write !,line
            kill sql
        } else {
            set sql($i(sql))=line
        }
    }
    if $$$ISERR(teststatus) {
        write !, "##########################"
        write !, "#### THERE ARE ERRORS ####"
        write !, "##########################"
        do $system.OBJ.DisplayError(teststatus)
    }
	quit teststatus
}

ClassMethod ExecuteSQL(ByRef sql, position)
{
    set statement=""
    for i=1:1:sql {
        set statement=statement_" "_sql(i)
    }
    write !, "POSITION: ",position
    write !, "STATEMENT: ",statement
    set ts=$zh
    set result=$system.SQL.Execute(.sql)
    write !,"TOTAL TIME: ",$zh-ts
    write !,"SQLCODE: ",result.%SQLCODE
    write !
    do result.%Display()
    write !
    if result.%SQLCODE>=0 {
        quit $$$OK
    } else {
        write !,"ERROR: "_result.%Message
        quit $$$ERROR($$$GeneralError,"ERROR: "_result.%Message_" STATEMENT: "_statement)
    }
}

}