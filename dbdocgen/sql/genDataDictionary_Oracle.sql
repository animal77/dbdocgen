declare
    page_title varchar2(100) := 'SSI Data Dictionary';
    table_or_view_not_exists exception;
    pragma exception_init (table_or_view_not_exists, -942);
begin
    /*
    begin
        execute immediate 'drop table markup';
    exception
        when table_or_view_not_exists then
            null;
    end;

    v_table_definition := q'<
      CREATE global temporary TABLE markup
      (
          id number GENERATED AS IDENTITY,
          text varchar2(32767)
      )
   >';
    execute immediate v_table_definition;
    */
    execute immediate 'truncate table markup';

    /*
    -- temp table to track primary key columns
    begin
        execute immediate 'drop table DOCGEN_keys';
    exception
        when table_or_view_not_exists then
            null;
    end;
    execute immediate 'create global temporary table DOCGEN_keys ( table_name varchar2(128), column_name varchar2(4000), p char(1))';
    */
    execute immediate 'truncate table DOCGEN_keys';

    insert into markup(text)
    values ('h1. Data Dictionary ');
    insert into markup(text)
    values ('h2. Database: ' || sys_context('USERENV', 'CURRENT_SCHEMA'));
    
-- ######################## DB LINKS ########################
    insert into markup(text) values ('h2. Database Links');
    insert into markup(text)
    SELECT '# ' || db_link
    from user_db_links
    order by db_link;

-- ######################## TABLES TOC ########################
    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Tables');
    insert into markup(text)
    SELECT '# [PT:' || page_title || '#' || table_name || ']'
    from user_tables
    order by table_name;

-- ######################## VIEWS TOC ########################
    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Views');
    insert into markup(text)
    SELECT '# [#' || view_name || ']'
    from user_views
    order by view_name;

-- ######################## ROUTINES TOC ########################
    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Functions');
    insert into markup(text)
    SELECT '# [#' || object_name || ']'
    from user_objects
    where object_type = 'FUNCTION'
    order by object_name;

    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Procedures');
    insert into markup(text)
    SELECT '# [#' || object_name || ']'
    from user_objects
    where object_type = 'PROCEDURE'
    order by object_name;

    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Packages');
    insert into markup(text)
    SELECT '# [#' || object_name || ']'
    from user_objects
    where object_type = 'PACKAGE'
    order by object_name;

-- ######################## Sequences ########################
    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Sequences');
    insert into markup(text)
    SELECT '# ' || sequence_name
    from user_sequences
    order by sequence_name;

-- ######################## Synonyms ########################
    insert into markup(text) values (chr(10));
    insert into markup(text) values ('h2. Synonyms');
    insert into markup(text)
    SELECT '# ' || synonym_name || ' → ' || decode(db_link, null, '', db_link || '.') || table_owner || '.' ||
           table_name
    from user_synonyms
    order by synonym_name;

-- ######################## TABLES DETAILS ########################
    insert into markup(text) values (chr(10));
    declare
        constraintCount number;
    begin
        -- temp table to track primary key columns
        insert into DOCGEN_keys
        select user_cons_columns.table_name,
               user_cons_columns.column_name,
               'P' as p
        from user_constraints,
             user_cons_columns
        where user_constraints.constraint_type = 'P'
          and user_constraints.constraint_name = user_cons_columns.constraint_name;

        for tbl in (select table_name from user_tables where TABLESPACE_NAME is not null order by table_name)
            loop
                insert into markup(text) values ('h3. ' || tbl.TABLE_NAME);
                -- table description
                insert into markup(text) select coalesce(comments,' ') from user_tab_comments where table_name = tbl.TABLE_NAME;
                -- table columns and types
                insert into markup(text) values ('|| ||Column Name||Type||Nullable||Default||Description||');
                insert into markup(text)
                select '|' || t1.COLUMN_ID || '|' || t1.column_name ||
                           decode(k.p, null, '', '(*' || k.p || '*)') || '|' ||
                       substr(t1.data_type || '(' || t1.data_length || ')', 0, 20) || '| ' ||
                       decode(t1.nullable, 'N', 'N', '') || '|' || /*SUBSTR(DATA_DEFAULT, 1, 4000) ||*/ ' ' ||
                       '| ' || t2.comments || '|'
                from user_tab_columns t1
                         join
                     user_col_comments t2 on t1.table_name = t2.table_name
                         and t1.column_name = t2.column_name
                         left join DOCGEN_keys k on k.TABLE_NAME = t1.TABLE_NAME and k.COLUMN_NAME = t1.COLUMN_NAME
                where t1.TABLE_NAME = tbl.TABLE_NAME
                ORDER BY t1.TABLE_NAME, COLUMN_ID;
                insert into markup(text) values (chr(10));

                -- key references from this table
                select count(1)
                into constraintCount
                from user_constraints
                where table_name = tbl.table_name
                  and CONSTRAINT_TYPE = 'R';
                if constraintCount > 0 then
                    insert into markup(text) values (chr(10));
                    insert into markup(text) values ('h4. Foreign Key References from ' || tbl.TABLE_NAME);
                    insert into markup(text) values ('||Name||Referring To||Column||Nullable||Referred By||');
                    insert into markup(text)
                    select '|' || c.CONSTRAINT_NAME || '|' || '[PT:' || page_title || '#' || ref_col.TABLE_NAME || '] |'
                               || ref_col.COLUMN_NAME || '|' || decode(tcol.NULLABLE, 'N', 'N', 'Y') || '|' ||
                           col.COLUMN_NAME || '|'
                    from USER_CONSTRAINTS C
                             inner join USER_CONS_COLUMNS col on col.CONSTRAINT_NAME = c.CONSTRAINT_NAME
                             inner join USER_CONS_COLUMNS ref_col ON ref_col.CONSTRAINT_NAME = c.R_CONSTRAINT_NAME
                             inner join user_tab_columns tcol
                                        ON tcol.TABLE_NAME = c.TABLE_NAME and tcol.COLUMN_NAME = col.COLUMN_NAME
                    where c.TABLE_NAME = tbl.TABLE_NAME
                      and c.CONSTRAINT_TYPE = 'R'
                    order by col.COLUMN_NAME;
                end if;

                -- key references to this table
                select count(1)
                into constraintCount
                from user_constraints
                where table_name = tbl.table_name
                  and CONSTRAINT_TYPE = 'R';
                if constraintCount > 0 then
                    insert into markup(text) values (chr(10));
                    insert into markup(text) values ('h4. Foreign Key References to ' || tbl.TABLE_NAME);
                    insert into markup(text) values ('||Name||Referred From||Column||Nullable||Column Referred||');
                    insert into markup(text)
                    select '|' || c.CONSTRAINT_NAME || '|' || '[PT:' || page_title || '#' || c.TABLE_NAME || '] |'
                               || ref_col.COLUMN_NAME || '|' || decode(tcol.NULLABLE, 'N', 'N', 'Y') || '|' ||
                           col.COLUMN_NAME || '|'
                    from USER_CONSTRAINTS c
                             inner join USER_CONS_COLUMNS col on c.R_CONSTRAINT_NAME = col.CONSTRAINT_NAME
                             inner join USER_CONS_COLUMNS ref_col on ref_col.CONSTRAINT_NAME = c.CONSTRAINT_NAME
                             inner join user_tab_columns tcol
                                        ON tcol.TABLE_NAME = c.TABLE_NAME and tcol.COLUMN_NAME = ref_col.COLUMN_NAME
                    where col.TABLE_NAME = tbl.TABLE_NAME
                      and c.CONSTRAINT_TYPE = 'R'
                    order by col.COLUMN_NAME, c.TABLE_NAME;
                end if;

                -- indexes on table
                insert into markup(text) values (chr(10));
                insert into markup(text) values ('h4. Indexes on ' || tbl.TABLE_NAME);
                insert into markup(text) values ('||Index Name||Column Name||Type|| Uniqueness||');
                insert into markup(text)
                select ' |' || ind_col.index_name || '|' ||
                       LISTAGG(ind_col.column_name, ', ') WITHIN GROUP (ORDER BY ind_col.column_name) || '|' ||
                       ind.INDEX_TYPE || '|' ||
                       ind.uniqueness || '| '
                       --exp.COLUMN_EXPRESSION,
                from USER_INDEXES ind
                         inner join
                     USER_IND_COLUMNS ind_col on ind.index_name = ind_col.index_name
                     --left join USER_IND_EXPRESSIONS exp on exp.INDEX_NAME = ind.INDEX_NAME
                where ind_col.table_name = tbl.TABLE_NAME
                group by ind_col.index_name, ind.uniqueness, ind.INDEX_TYPE;

            end loop;
    END;
/*
C - Check constraint on a table
P - Primary key
U - Unique key
R - Referential integrity
V - With check option, on a view
O - With read only, on a view
H - Hash expression
F - Constraint that involves a REF column
S - Supplemental logging

// TODO: Views, Functions, Procedures
*/
end;
/

select text  from MARKUP order by id
