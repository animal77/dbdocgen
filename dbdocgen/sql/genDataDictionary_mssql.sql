set nocount on

IF OBJECT_ID('tempdb..#markup', 'U') IS NOT NULL
    drop TABLE #markup
create table #markup
(
    id   INT IDENTITY (1, 1) primary key,
    text Varchar(max)
)

DECLARE tblCursor CURSOR FOR
    SELECT TABLE_NAME, TABLE_SCHEMA
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA IN ('dbo')
      and TABLE_TYPE in ('BASE TABLE')
    order by table_schema, table_name

declare
    @table_name nvarchar(128), @table_schema nvarchar(128)

IF OBJECT_ID('tempdb..#keys', 'U') IS NOT NULL
    drop TABLE #keys

CREATE TABLE #keys
(
    table_catalog nvarchar(128),
    table_schema  nvarchar(128),
    table_name    nvarchar(128),
    column_name   nvarchar(128),
    constraints   varchar(100)
)

insert #keys
SELECT ku.TABLE_CATALOG,
       ku.TABLE_SCHEMA,
       ku.TABLE_NAME,
       ku.COLUMN_NAME,
       string_agg(case
                      when tc.CONSTRAINT_TYPE = 'FOREIGN KEY' THEN 'FK'
                      when tc.CONSTRAINT_TYPE = 'PRIMARY KEY' then 'PK'
                      else tc.CONSTRAINT_TYPE END, ', ')
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS tc
         INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE AS ku
                    ON tc.CONSTRAINT_TYPE in ('PRIMARY KEY', 'FOREIGN KEY')
                        AND tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
group by ku.TABLE_CATALOG, ku.TABLE_SCHEMA, ku.TABLE_NAME, ku.COLUMN_NAME
order by table_name

OPEN tblCursor
FETCH NEXT FROM tblCursor INTO @table_name, @table_schema;

declare
    @tabSchema as nvarchar(500)

insert #markup
values ('h1.Data Dictionary ')
insert #markup
values ('h2.Database: ' + DB_NAME())


-- ######################## TABLES TOC ########################
insert #markup
values ('h2.Tables')
insert #markup
SELECT '# [' + table_schema + '.' + table_name + '|#' + table_schema + '.' + table_name + ']'
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('dbo')
  and TABLE_TYPE in ('BASE TABLE')
order by table_schema, table_name


-- ######################## VIEWS TOC ########################
insert into #markup
values (CHAR(13) + 'h2. Views')
insert #markup
SELECT '# [' + table_schema + '.' + table_name + '|#' + table_schema + '.' + table_name + ']'
from INFORMATION_SCHEMA.VIEWS v
WHERE TABLE_SCHEMA IN ('dbo')
order by table_schema, table_name


-- ######################## ROUTINES TOC ########################
insert #markup
values (CHAR(13) + 'h2. Functions')
insert #markup
SELECT '# [' + routine_schema + '.' + routine_name + '|#' + routine_schema + '.' + routine_name + ']'
FROM INFORMATION_SCHEMA.ROUTINES
WHERE routine_schema IN ('dbo')
  and routine_type = 'FUNCTION'
order by routine_schema, routine_name

insert #markup
values (CHAR(13) + 'h2. Procedures')
insert #markup
SELECT '# [' + routine_schema + '.' + routine_name + '|#' + routine_schema + '.' + routine_name + ']'
FROM INFORMATION_SCHEMA.ROUTINES
WHERE routine_schema IN ('dbo')
  and routine_type = 'PROCEDURE'
order by routine_schema, routine_name

-- ######################## TABLES DETAILS ########################
WHILE @@FETCH_STATUS = 0
BEGIN
    insert into #markup values (char(13))
    set @tabSchema = (@table_schema + '.' + @table_name)
    insert into #markup values ('h3. ' + @tabSchema)
    insert into #markup
        SELECT coalesce(CAST(ep.value AS nvarchar(max)), ' ')
        FROM sys.objects obj
        LEFT JOIN sys.extended_properties ep ON obj.object_id = ep.major_id
        WHERE obj.type = 'U'  -- 'U' indicates user table
            and ep.minor_id = 0
            and ep.name = 'MS_Description'
            AND ep.major_id = OBJECT_ID(@table_name); -- Replace 'YourTableName' with the name of your table


    insert into #markup values ('|| ||Column Name||Type||Nullable||default||Description||')
    insert into #markup
    select concat('|', c.ordinal_position, '|', c.COLUMN_NAME)
               + CASE WHEN keys.COLUMN_NAME IS NOT NULL THEN ' *(' + keys.constraints + ')*' ELSE '' END
               + '|' + DATA_TYPE +
           case
               when data_type not in ('bit', 'date', 'datetime', 'datetime2', 'ntext', 'smalldatetime', 'time', 'xml')
                   then
                       '(' +
                       case
                           when data_type in ('decimal', 'float', 'numeric', 'real')
                               then concat(numeric_precision, ',', numeric_scale)
                           when data_type in ('char', 'nchar', 'nvarchar', 'text', 'varchar')
                               then concat('', CASE 
                                           WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX'
                                           ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10))
                                           END)
                           when data_type in ('bigint', 'float', 'int', 'real', 'smallint', 'tinyint')
                               then concat('', NUMERIC_PRECISION)
                           end
                       + ')'
               else ''                      
               end
               + '|' + IS_NULLABLE + '|' + coalesce(SUBSTRING(COLUMN_DEFAULT, 2, LEN(COLUMN_DEFAULT) - 2), ' ')
               + '|' +  coalesce(CAST(ep.value AS nvarchar(max)), ' ') + '|'
    from INFORMATION_SCHEMA.COLUMNS c
    LEFT JOIN #keys keys
        ON c.TABLE_CATALOG = keys.TABLE_CATALOG
        AND c.TABLE_SCHEMA = keys.TABLE_SCHEMA
        AND c.TABLE_NAME = keys.TABLE_NAME
        AND c.COLUMN_NAME = keys.COLUMN_NAME
    LEFT JOIN sys.extended_properties ep
        ON ep.major_id = OBJECT_ID(@table_name)
        AND ep.minor_id = COLUMNPROPERTY(OBJECT_ID(@table_name), c.column_name, 'ColumnID')
        AND ep.class = 1 -- object or column
        AND ep.name = 'MS_Description'
    WHERE c.TABLE_NAME = @table_name
      and c.TABLE_SCHEMA = @table_schema

    -- key references from this table
    insert #markup values (char(13))
    insert into #markup values ('h4. Foreign Key References from ' + @tabSchema)
    insert into #markup values ('||Name|| Referring To||Column||Nullable||Referred By||')
    insert into #markup
    SELECT '|' + OBJECT_NAME(constraint_object_id) + '|' + -- Constraint Name
           '[' + OBJECT_NAME(referenced_object_id) + '| #' + @table_schema + '.' + OBJECT_NAME(referenced_object_id) +
           '] |' + -- Referenced Object
           COL_NAME(referenced_object_id, referenced_column_id) + '|' + -- Referenced Column Name
           + case
                 when COLUMNPROPERTY(parent_object_id, COL_NAME(parent_object_id, parent_column_id), 'AllowsNull') = 0
                     then 'NO'
                 else 'YES' end + '|' + -- Nullable
           COL_NAME(parent_object_id, parent_column_id) + '|' -- Referencing Column Name
    FROM sys.foreign_key_columns
    where parent_object_id = OBJECT_ID(@tabSchema)
    order by OBJECT_NAME(referenced_object_id), COL_NAME(referenced_object_id, referenced_column_id)

    -- key references to this table
    insert #markup values (char(13))
    insert into #markup values ('h4. Foreign Keys References to ' + @tabSchema)
    insert into #markup values ('||Name|| Referred From||Column||Nullable|| Column Referred||')
    insert into #markup
    SELECT '|' + OBJECT_NAME(constraint_object_id) + '|' + -- Constraint Name
           '[' + OBJECT_NAME(parent_object_id) + '| #' + @table_schema + '.' + OBJECT_NAME(parent_object_id) +
           '] |' + -- Referencing Table
           COL_NAME(parent_object_id, parent_column_id) + '|' + -- Referencing Column Name
           + case
                 when COLUMNPROPERTY(parent_object_id, COL_NAME(parent_object_id, parent_column_id), 'AllowsNull') = 0
                     then 'NO'
                 else 'YES' end + '|' + -- Nullable
           COL_NAME(referenced_object_id, referenced_column_id) + '|' -- Referenced Column Name
    FROM sys.foreign_key_columns
    where referenced_object_id = OBJECT_ID(@tabSchema)
    order by OBJECT_NAME(parent_object_id), COL_NAME(parent_object_id, parent_column_id)

    -- indexes on table
    insert #markup values (char(13))
    insert into #markup values ('h4. Indexes on ' + @tabSchema)
    insert into #markup values ('||Index Name||Type||Column Name||Included Column||')
    insert into #markup
    SELECT '|' + case when ic.index_column_id = 1 then i.name else '' end + '|' + -- Index Name
           case
               when ic.index_column_id > 1 then ''
               when i.is_primary_key = 1 then 'PK'
               when i.is_unique = 1 then 'UN'
               else '' end + '|' + -- Type
           COL_NAME(ic.object_id, ic.column_id) + '|' + -- Column Name
           case when ic.is_included_column = 1 then 'Y' else ' ' end + '|' -- Is included Column
    FROM sys.indexes AS i
             INNER JOIN sys.index_columns AS ic
                        ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    WHERE i.object_id = OBJECT_ID(@tabSchema)

    FETCH NEXT FROM tblCursor INTO @table_name, @table_schema;
END
CLOSE tblCursor
DEALLOCATE tblCursor

-- ######################## VIEWS DETAILS ########################
insert #markup
values ('h2. Views')

DECLARE viewCursor CURSOR FOR
    SELECT TABLE_NAME, TABLE_SCHEMA
    FROM INFORMATION_SCHEMA.VIEWS
    WHERE TABLE_SCHEMA IN ('dbo')
    order by table_schema, table_name

OPEN viewCursor
FETCH NEXT FROM viewCursor INTO @table_name, @table_schema;

WHILE @@FETCH_STATUS = 0
BEGIN
    insert #markup values (char(13))
    set @tabSchema = (@table_schema + '.' + @table_name)
    insert into #markup values ('h3. ' + @tabSchema)
    insert into #markup values ('|| ||Column Name||Type||Nullable||Description||')
    insert into #markup
    select '|' + concat(c.ordinal_position, '|', c.COLUMN_NAME, '|', c.DATA_TYPE) +
           case
               when c.data_type not in ('bit', 'date', 'datetime', 'datetime2', 'ntext', 'smalldatetime', 'time', 'xml')
                   then
                       '(' +
                       case
                           when data_type in ('decimal', 'float', 'numeric', 'real')
                               then concat(numeric_precision, ',', numeric_scale)
                           when data_type in ('char', 'nchar', 'nvarchar', 'text', 'varchar')
                               then concat('', CASE 
                                           WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX'
                                           ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10))
                                           END)
                           when data_type in ('bigint', 'float', 'int', 'real', 'smallint', 'tinyint')
                               then concat('', NUMERIC_PRECISION)
                           end
                       + ')'
               else ''
               end
               + '|' + IS_NULLABLE + '| |'
    from INFORMATION_SCHEMA.VIEWS v
             join INFORMATION_SCHEMA.COLUMNS c
                  on v.TABLE_CATALOG = c.TABLE_CATALOG and v.TABLE_SCHEMA = c.TABLE_SCHEMA and
                     v.TABLE_NAME = c.TABLE_NAME
    WHERE v.TABLE_NAME = @table_name
      and v.TABLE_SCHEMA = @table_schema

    FETCH NEXT FROM viewCursor INTO @table_name, @table_schema;
END
CLOSE viewCursor
DEALLOCATE viewCursor;


-- ######################## FUNCTION DETAILS ########################
insert #markup
values ('h2. Functions')
insert into #markup
values ('|| ||Function Name||Return Type||Last Modified||Description||')
insert into #markup
SELECT '|' + convert(varchar(20), ROW_NUMBER() over (order by routine_schema, routine_name)) + '|h4. ' 
        + routine_schema + '.' + routine_name + '|' + DATA_TYPE +
       case
           when data_type not in
                ('bit', 'date', 'datetime', 'datetime2', 'ntext', 'smalldatetime', 'table', 'time', 'xml')
               then
                   '(' +
                   case
                       when data_type in ('decimal', 'float', 'numeric', 'real')
                           then concat(numeric_precision, ',', numeric_scale)
                       when data_type in ('char', 'nchar', 'nvarchar', 'text', 'varchar')
                           then concat('', CASE 
                                           WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX'
                                           ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10))
                                           END)
                       when data_type in ('bigint', 'float', 'int', 'real', 'smallint', 'tinyint')
                           then concat('', NUMERIC_PRECISION)
                       end
                   + ')'
           else ''
           end
           + '|' + convert(varchar(20), LAST_ALTERED) + '| |'
FROM INFORMATION_SCHEMA.ROUTINES
WHERE routine_schema IN ('dbo')
  and routine_type = 'FUNCTION'
order by routine_schema, routine_name

-- ######################## PROCEDURE DETAILS ########################
insert #markup
values ('h2.Procedures')
insert into #markup
values ('|| ||Procedure Name||Last Modified||Description||')
insert into #markup
SELECT '|' + convert(varchar(20), ROW_NUMBER() over (order by routine_schema, routine_name)) + '|h4. ' + routine_schema + '.' + routine_name + '|'
           + convert(varchar(20), LAST_ALTERED) + '| |'
FROM INFORMATION_SCHEMA.ROUTINES
WHERE routine_schema IN ('dbo')
  and routine_type = 'PROCEDURE'
order by routine_schema, routine_name


select text
from #markup
order by id

/*
select * from #keys

SELECT
    OBJECT_NAME(referenced_object_id) as 'Referenced Object',
    COL_NAME(referenced_object_id, referenced_column_id) 'Referenced Column Name',
	OBJECT_NAME(parent_object_id) as 'Referencing Object',
    COL_NAME(parent_object_id, parent_column_id) as 'Referencing Column Name',
    OBJECT_NAME(constraint_object_id) 'Constraint Name'
FROM sys.foreign_key_columns
order by OBJECT_NAME(referenced_object_id) ,OBJECT_NAME(parent_object_id)

select case when COLUMNPROPERTY(referenced_object_id, COL_NAME(referenced_object_id, referenced_column_id), 'AllowsNull') = 0 then 'N' else 'Y' end

select * from  INFORMATION_SCHEMA.VIEWS v
select c.* from INFORMATION_SCHEMA.VIEWS v join INFORMATION_SCHEMA.COLUMNS c on v.TABLE_CATALOG = c.TABLE_CATALOG and v.TABLE_SCHEMA = c.TABLE_SCHEMA
and c.TABLE_NAME = v.TABLE_NAME

select * from  INFORMATION_SCHEMA.routines WHERE routine_schema IN ('dbo')  and routine_type = 'FUNCTION'
*/
