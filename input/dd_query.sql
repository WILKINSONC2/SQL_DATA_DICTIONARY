SET NOCOUNT ON

/* Begin Parmeters

DECLARE @enable_tables BIT = 1
DECLARE @enable_views BIT = 1
DECLARE @enable_triggers BIT = 1
DECLARE @enable_procs BIT = 1

End Parameters */

DECLARE @database_name NVARCHAR(max)
DECLARE @schema_name NVARCHAR(max)
DECLARE @object_name NVARCHAR(max)

DECLARE @markdown TABLE (
      line_no BIGINT identity(1, 1)
    , line_msg NVARCHAR(max)
    )

INSERT INTO @markdown (line_msg)
SELECT '# Database: ' + UPPER(DB_NAME())

INSERT INTO @markdown (line_msg)
SELECT CONCAT (
        d.name
        , ' was created on '
        , FORMAT(d.create_date, 'dd-MMM-yyyy')
        , ' with a collation type of ['
        , collation_name
        , '].'
        )
FROM sys.databases d
WHERE d.name = DB_NAME()

INSERT INTO @markdown (line_msg)
SELECT 'The database is ' + IIF(d.is_encrypted=1,'','NOT ') + 'encrypted, '
FROM sys.databases d
WHERE d.name = DB_NAME()

INSERT INTO @markdown (line_msg)
SELECT 'and the database does ' + IIF(d.is_fulltext_enabled=1,'','NOT ') + 'have fulltext seach enabled.'
FROM sys.databases d
WHERE d.name = DB_NAME()

INSERT INTO @markdown (line_msg)
SELECT 'The database was reported as being ' + d.state_desc + ' when this document was generated at ' + FORMAT(CURRENT_TIMESTAMP,'HH:mm dd/MMM/yyyy') + '. </br> </br>'
FROM sys.databases d
WHERE d.name = DB_NAME()

-- TABLES SECTION
-- ==============

IF EXISTS (
        SELECT NULL
        FROM sys.tables tab
        INNER JOIN (
            SELECT DISTINCT p.object_id
                , sum(p.rows) rows
            FROM sys.tables t
            INNER JOIN sys.partitions p
                ON p.object_id = t.object_id
            GROUP BY p.object_id
                , p.index_id
            ) p
            ON p.object_id = tab.object_id
        LEFT JOIN sys.extended_properties ep
            ON tab.object_id = ep.major_id
                AND ep.name = 'MS_Description'
                AND ep.minor_id = 0
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        ) AND @enable_tables = 1
BEGIN

    INSERT INTO @markdown (line_msg)
    SELECT '## Tables'

    INSERT INTO @markdown (line_msg)
    SELECT '### Overview'

    INSERT INTO @markdown (line_msg)
    SELECT '|schema|table name|created date|modified date|rows|description|'

    INSERT INTO @markdown (line_msg)
    SELECT '|---|---|---|---|---|---|'

    INSERT INTO @markdown (line_msg)
    SELECT CONCAT (
            '|'
            , convert(VARCHAR(255), schema_name(tab.schema_id)) -- as schema_name
            , '|'
            , convert(VARCHAR(255), tab.name) -- as table_name 
            , '|'
            , FORMAT(tab.create_date, 'yyyy-MM-dd') -- as created
            , '|'
            , FORMAT(tab.modify_date, 'yyyy-MM-dd') -- as last_modified
            , '|'
            , CONVERT(VARCHAR(20), p.rows) -- as num_rows
            , '|'
            , convert(VARCHAR(255), ep.value) -- as comments 
            , '|'
            )
    FROM sys.tables tab
    INNER JOIN (
        SELECT DISTINCT p.object_id
            , sum(p.rows) rows
        FROM sys.tables t
        INNER JOIN sys.partitions p
            ON p.object_id = t.object_id
        GROUP BY p.object_id
            , p.index_id
        ) p
        ON p.object_id = tab.object_id
    LEFT JOIN sys.extended_properties ep
        ON tab.object_id = ep.major_id
            AND ep.name = 'MS_Description'
            AND ep.minor_id = 0
            AND ep.class_desc = 'OBJECT_OR_COLUMN'
    ORDER BY schema_name(tab.schema_id)
        , tab.name;

    DECLARE object_cursor CURSOR
    FOR

    -- tables overview 
    SELECT schema_name(tab.schema_id) -- as schema_name,
        , tab.name -- as table_name, 
    FROM sys.tables tab
    INNER JOIN (
        SELECT DISTINCT p.object_id
            , sum(p.rows) rows
        FROM sys.tables t
        INNER JOIN sys.partitions p
            ON p.object_id = t.object_id
        GROUP BY p.object_id
            , p.index_id
        ) p
        ON p.object_id = tab.object_id
    LEFT JOIN sys.extended_properties ep
        ON tab.object_id = ep.major_id
            AND ep.name = 'MS_Description'
            AND ep.minor_id = 0
            AND ep.class_desc = 'OBJECT_OR_COLUMN'
    ORDER BY schema_name(tab.schema_id)
        , tab.name;

    OPEN object_cursor;

    FETCH NEXT
    FROM object_cursor
    INTO @schema_name
        , @object_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN

        -- tables detail
        INSERT INTO @markdown (line_msg)
        SELECT CONCAT (
                '### '
                , @schema_name
                , '.'
                , @object_name
                )

        INSERT INTO @markdown (line_msg)
        SELECT '|column name|data type|nullable|default|primary key|foreign key|unique key|check constraint|column definition|description|'

        INSERT INTO @markdown (line_msg)
        SELECT '|---|---|---|---|---|---|---|---|---|---|'

        -- table details
        INSERT INTO @markdown (line_msg)
        SELECT CONCAT (
                '|'
                , CONVERT(NVARCHAR(MAX), col.name) -- as column_name, 
                -- , '|', CONVERT(NVARCHAR(MAX),t.name) -- as data_type,    
                , '|'
                , t.name + CASE 
                    WHEN t.is_user_defined = 0
                        THEN isnull('(' + CASE 
                                    WHEN t.name IN ('binary', 'char', 'nchar', 'varchar', 'nvarchar', 'varbinary')
                                        THEN CASE col.max_length
                                                WHEN - 1
                                                    THEN 'MAX'
                                                ELSE CASE 
                                                        WHEN t.name IN ('nchar', 'nvarchar')
                                                            THEN cast(col.max_length / 2 AS VARCHAR(4))
                                                        ELSE cast(col.max_length AS VARCHAR(4))
                                                        END
                                                END
                                    WHEN t.name IN ('datetime2', 'datetimeoffset', 'time')
                                        THEN cast(col.scale AS VARCHAR(4))
                                    WHEN t.name IN ('decimal', 'numeric')
                                        THEN cast(col.precision AS VARCHAR(4)) + ', ' + cast(col.scale AS VARCHAR(4))
                                    END + ')', '')
                    ELSE ':' + (
                            SELECT c_t.name + isnull('(' + CASE 
                                        WHEN c_t.name IN ('binary', 'char', 'nchar', 'varchar', 'nvarchar', 'varbinary')
                                            THEN CASE c.max_length
                                                    WHEN - 1
                                                        THEN 'MAX'
                                                    ELSE CASE 
                                                            WHEN t.name IN ('nchar', 'nvarchar')
                                                                THEN cast(c.max_length / 2 AS VARCHAR(4))
                                                            ELSE cast(c.max_length AS VARCHAR(4))
                                                            END
                                                    END
                                        WHEN c_t.name IN ('datetime2', 'datetimeoffset', 'time')
                                            THEN cast(c.scale AS VARCHAR(4))
                                        WHEN c_t.name IN ('decimal', 'numeric')
                                            THEN cast(c.precision AS VARCHAR(4)) + ', ' + cast(c.scale AS VARCHAR(4))
                                        END + ')', '')
                            FROM sys.columns AS c
                            INNER JOIN sys.types AS c_t
                                ON c.system_type_id = c_t.user_type_id
                            WHERE c.object_id = col.object_id
                                AND c.column_id = col.column_id
                                AND c.user_type_id = col.user_type_id
                            )
                    END -- as data_type_ext,
                , '|'
                , CASE 
                    WHEN col.is_nullable = 0
                        THEN 'N'
                    ELSE 'Y'
                    END -- as nullable,
                , '|'
                , CASE 
                    WHEN def.DEFINITION IS NOT NULL
                        THEN def.DEFINITION
                    ELSE ''
                    END -- as default_value,
                , '|'
                , CASE 
                    WHEN pk.column_id IS NOT NULL
                        THEN 'PK'
                    ELSE ''
                    END -- as primary_key, 
                , '|'
                , CASE 
                    WHEN fk.parent_column_id IS NOT NULL
                        THEN 'FK'
                    ELSE ''
                    END -- as foreign_key, 
                , '|'
                , CASE 
                    WHEN uk.column_id IS NOT NULL
                        THEN 'UK'
                    ELSE ''
                    END -- as unique_key,
                , '|'
                , CASE 
                    WHEN ch.check_const IS NOT NULL
                        THEN ch.check_const
                    ELSE ''
                    END -- as check_contraint,
                , '|'
                , CONVERT(NVARCHAR(MAX), cc.DEFINITION) -- as computed_column_definition,
                , '|'
                , CONVERT(NVARCHAR(MAX), ep.value) -- as comments,
                , '|'
                )
        FROM sys.tables AS tab
        LEFT JOIN sys.columns AS col
            ON tab.object_id = col.object_id
        LEFT JOIN sys.types AS t
            ON col.user_type_id = t.user_type_id
        LEFT JOIN sys.default_constraints AS def
            ON def.object_id = col.default_object_id
        LEFT JOIN (
            SELECT index_columns.object_id
                , index_columns.column_id
            FROM sys.index_columns
            INNER JOIN sys.indexes
                ON index_columns.object_id = indexes.object_id
                    AND index_columns.index_id = indexes.index_id
            WHERE indexes.is_primary_key = 1
            ) AS pk
            ON col.object_id = pk.object_id
                AND col.column_id = pk.column_id
        LEFT JOIN (
            SELECT fc.parent_column_id
                , fc.parent_object_id
            FROM sys.foreign_keys AS f
            INNER JOIN sys.foreign_key_columns AS fc
                ON f.object_id = fc.constraint_object_id
            GROUP BY fc.parent_column_id
                , fc.parent_object_id
            ) AS fk
            ON fk.parent_object_id = col.object_id
                AND fk.parent_column_id = col.column_id
        LEFT JOIN (
            SELECT c.parent_column_id
                , c.parent_object_id
                , 'Check' check_const
            FROM sys.check_constraints AS c
            GROUP BY c.parent_column_id
                , c.parent_object_id
            ) AS ch
            ON col.column_id = ch.parent_column_id
                AND col.object_id = ch.parent_object_id
        LEFT JOIN (
            SELECT index_columns.object_id
                , index_columns.column_id
            FROM sys.index_columns
            INNER JOIN sys.indexes
                ON indexes.index_id = index_columns.index_id
                    AND indexes.object_id = index_columns.object_id
            WHERE indexes.is_unique_constraint = 1
            GROUP BY index_columns.object_id
                , index_columns.column_id
            ) AS uk
            ON col.column_id = uk.column_id
                AND col.object_id = uk.object_id
        LEFT JOIN sys.extended_properties AS ep
            ON tab.object_id = ep.major_id
                AND col.column_id = ep.minor_id
                AND ep.name = 'MS_Description'
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        LEFT JOIN sys.computed_columns AS cc
            ON tab.object_id = cc.object_id
                AND col.column_id = cc.column_id
        WHERE schema_name(tab.schema_id) = @schema_name
            AND tab.name = @object_name

        IF EXISTS (
                SELECT NULL
                FROM sys.tables AS tab
                INNER JOIN sys.foreign_keys AS fk
                    ON tab.object_id = fk.parent_object_id
                INNER JOIN sys.foreign_key_columns AS fkc
                    ON fk.object_id = fkc.constraint_object_id
                INNER JOIN sys.columns AS col
                    ON fkc.parent_object_id = col.object_id
                        AND fkc.parent_column_id = col.column_id
                INNER JOIN sys.columns AS col_prim
                    ON fkc.referenced_object_id = col_prim.object_id
                        AND fkc.referenced_column_id = col_prim.column_id
                INNER JOIN sys.tables AS tab_prim
                    ON fk.referenced_object_id = tab_prim.object_id
                WHERE schema_name(tab.schema_id) = @schema_name
                    AND tab.name = @object_name
                )
        BEGIN
            INSERT INTO @markdown (line_msg)
            SELECT '#### Foreign Keys'

            INSERT INTO @markdown (line_msg)
            SELECT '|constraint name|column name|originating schema|originating table|originating column|join conidtions|complex key|fk id|'

            INSERT INTO @markdown (line_msg)
            SELECT '|---|---|---|---|---|---|---|---|'

            -- tables fks
            INSERT INTO @markdown (line_msg)
            SELECT CONCAT (
                    --   '|' , schema_name(tab.schema_id) -- as table_schema_name,
                    -- , '|' , tab.name -- as table_name,
                    '|'
                    , fk.name -- as constraint_name,
                    , '|'
                    , col.name -- as column_name,
                    , '|'
                    , schema_name(tab_prim.schema_id) -- as primary_table_schema_name,
                    , '|'
                    , tab_prim.name -- as primary_table_name,
                    , '|'
                    , col_prim.name -- as primary_table_column, 
                    , '|'
                    , schema_name(tab.schema_id) + '.' + tab.name + '.' + col.name + ' = ' + schema_name(tab_prim.schema_id) + '.' + tab_prim.name + '.' + col_prim.name -- as join_condition,
                    , '|'
                    , CASE 
                        WHEN count(*) OVER (PARTITION BY fk.name) > 1
                            THEN 'Y'
                        ELSE 'N'
                        END -- as complex_fk,
                    , '|'
                    , fkc.constraint_column_id -- as fk_part
                    , '|'
                    )
            FROM sys.tables AS tab
            INNER JOIN sys.foreign_keys AS fk
                ON tab.object_id = fk.parent_object_id
            INNER JOIN sys.foreign_key_columns AS fkc
                ON fk.object_id = fkc.constraint_object_id
            INNER JOIN sys.columns AS col
                ON fkc.parent_object_id = col.object_id
                    AND fkc.parent_column_id = col.column_id
            INNER JOIN sys.columns AS col_prim
                ON fkc.referenced_object_id = col_prim.object_id
                    AND fkc.referenced_column_id = col_prim.column_id
            INNER JOIN sys.tables AS tab_prim
                ON fk.referenced_object_id = tab_prim.object_id
            WHERE schema_name(tab.schema_id) = @schema_name
                AND tab.name = @object_name
            ORDER BY fk.name -- as constraint_name,
                , schema_name(tab.schema_id) -- as table_schema_name,
                , tab.name -- as table_name,
                , col.name -- as column_name,

            -- tables fk graph
            INSERT INTO @markdown (line_msg)
            SELECT '```mermaid'

            INSERT INTO @markdown (line_msg)
            SELECT 'graph LR'

            INSERT INTO @markdown (line_msg)
            SELECT DISTINCT CONCAT (
                    @schema_name + '.'
                    , @object_name
                    , ' --> '
                    , schema_name(tab_prim.schema_id) -- as primary_table_schema_name,
                    , '.'
                    , tab_prim.name -- as primary_table_name,
                    )
            FROM sys.tables AS tab
            INNER JOIN sys.foreign_keys AS fk
                ON tab.object_id = fk.parent_object_id
            INNER JOIN sys.foreign_key_columns AS fkc
                ON fk.object_id = fkc.constraint_object_id
            INNER JOIN sys.columns AS col
                ON fkc.parent_object_id = col.object_id
                    AND fkc.parent_column_id = col.column_id
            INNER JOIN sys.columns AS col_prim
                ON fkc.referenced_object_id = col_prim.object_id
                    AND fkc.referenced_column_id = col_prim.column_id
            INNER JOIN sys.tables AS tab_prim
                ON fk.referenced_object_id = tab_prim.object_id
            WHERE schema_name(tab.schema_id) = @schema_name
                AND tab.name = @object_name

            INSERT INTO @markdown (line_msg)
            SELECT '```'
        END

        -- tables indexes
        IF EXISTS (
                SELECT NULL
                FROM sys.indexes i
                LEFT JOIN sys.index_columns ic
                    ON ic.object_id = i.object_id
                        AND ic.index_id = i.index_id
                LEFT JOIN sys.columns c
                    ON c.object_id = ic.object_id
                        AND c.column_id = ic.column_id
                WHERE i.object_id = object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                    AND i.is_unique = 1
                )
        BEGIN
            INSERT INTO @markdown (line_msg)
            SELECT '#### Indexes'

            INSERT INTO @markdown (line_msg)
            SELECT '|index name|index type|key position|indexed column|included column|'

            INSERT INTO @markdown (line_msg)
            SELECT '|---|---|---|---|---|'

            -- tables indexes
            INSERT INTO @markdown (line_msg)
            SELECT CONCAT (
                    '|'
                    , i.name --as index_name
                    , '|'
                    , i.type_desc -- as index_type
                    , '|'
                    , ic.key_ordinal -- as IndexColumnPosition
                    , '|'
                    , c.name -- as IndexColumnName
                    , '|'
                    , IIF(ic.is_included_column = 1, 'Y', 'N') --as included_column
                    , '|'
                    )
            FROM sys.indexes i
            LEFT JOIN sys.index_columns ic
                ON ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
            LEFT JOIN sys.columns c
                ON c.object_id = ic.object_id
                    AND c.column_id = ic.column_id
            WHERE i.object_id = object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))
                AND i.is_unique = 1
            ORDER BY i.type_desc -- as index_type
                , i.name -- as IndexName
                , ic.key_ordinal -- as IndexColumnPosition
        END

        FETCH NEXT
        FROM object_cursor
        INTO @schema_name
            , @object_name;
    END;

    CLOSE object_cursor;
    DEALLOCATE object_cursor;

END

-- VIEWS SECTION
-- ==============

IF EXISTS (
        SELECT NULL
        FROM sys.VIEWS v
        LEFT JOIN sys.extended_properties ep
            ON v.object_id = ep.major_id
                AND ep.name = 'MS_Description'
                AND ep.minor_id = 0
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        INNER JOIN sys.sql_modules m
            ON m.object_id = v.object_id
        ) AND @enable_views = 1
BEGIN
    INSERT INTO @markdown (line_msg)
    SELECT '## Views'

    INSERT INTO @markdown (line_msg)
    SELECT '### Overview'

    INSERT INTO @markdown (line_msg)
    SELECT '|schema|view name|created date|modified date|description|'

    INSERT INTO @markdown (line_msg)
    SELECT '|---|---|---|---|---|'

    -- views overview
    INSERT INTO @markdown (line_msg)
    SELECT CONCAT (
            '|'
            , schema_name(v.schema_id) -- as schema_name,
            , '|'
            , v.name -- as view_name,
            , '|'
            , v.create_date -- as created,
            , '|'
            , v.modify_date -- as last_modified,
            --,'|',m.definition,
            , '|'
            , CONVERT(VARCHAR(MAX), ep.value) -- as comments
            , '|'
            )
    FROM sys.VIEWS v
    LEFT JOIN sys.extended_properties ep
        ON v.object_id = ep.major_id
            AND ep.name = 'MS_Description'
            AND ep.minor_id = 0
            AND ep.class_desc = 'OBJECT_OR_COLUMN'
    INNER JOIN sys.sql_modules m
        ON m.object_id = v.object_id
    ORDER BY schema_name(v.schema_id)
        , v.name;

    DECLARE object_cursor CURSOR
    FOR
    
    -- views
    SELECT schema_name(v.schema_id) -- as schema_name,
        , v.name -- as table_name, 
    FROM sys.VIEWS v
    LEFT JOIN sys.extended_properties ep
        ON v.object_id = ep.major_id
            AND ep.name = 'MS_Description'
            AND ep.minor_id = 0
            AND ep.class_desc = 'OBJECT_OR_COLUMN'
    INNER JOIN sys.sql_modules m
        ON m.object_id = v.object_id
    ORDER BY schema_name(v.schema_id)
        , v.name;

    OPEN object_cursor;

    FETCH NEXT
    FROM object_cursor
    INTO @schema_name
        , @object_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN

        -- views detail
        INSERT INTO @markdown (line_msg)
        SELECT CONCAT (
                '### '
                , @schema_name
                , '.'
                , @object_name
                )

        INSERT INTO @markdown (line_msg)
        SELECT '|column name|data type|nullable|description|'

        INSERT INTO @markdown (line_msg)
        SELECT '|---|---|---|---|'

        -- views details
        INSERT INTO @markdown (line_msg)
        SELECT CONCAT (
                -- '|',  schema_name(v.schema_id) -- as schema_name,
                -- '|',  v.name -- as view_name, 
                '|'
                , col.name -- as column_name,
                , '|'
                , t.name + CASE 
                    WHEN t.is_user_defined = 0
                        THEN isnull('(' + CASE 
                                    WHEN t.name IN ('binary', 'char', 'nchar', 'varchar', 'nvarchar', 'varbinary')
                                        THEN CASE col.max_length
                                                WHEN - 1
                                                    THEN 'MAX'
                                                ELSE CASE 
                                                        WHEN t.name IN ('nchar', 'nvarchar')
                                                            THEN cast(col.max_length / 2 AS VARCHAR(4))
                                                        ELSE cast(col.max_length AS VARCHAR(4))
                                                        END
                                                END
                                    WHEN t.name IN ('datetime2', 'datetimeoffset', 'time')
                                        THEN cast(col.scale AS VARCHAR(4))
                                    WHEN t.name IN ('decimal', 'numeric')
                                        THEN cast(col.precision AS VARCHAR(4)) + ', ' + cast(col.scale AS VARCHAR(4))
                                    END + ')', '')
                    ELSE ':' + (
                            SELECT c_t.name + isnull('(' + CASE 
                                        WHEN c_t.name IN ('binary', 'char', 'nchar', 'varchar', 'nvarchar', 'varbinary')
                                            THEN CASE c.max_length
                                                    WHEN - 1
                                                        THEN 'MAX'
                                                    ELSE CASE 
                                                            WHEN t.name IN ('nchar', 'nvarchar')
                                                                THEN cast(c.max_length / 2 AS VARCHAR(4))
                                                            ELSE cast(c.max_length AS VARCHAR(4))
                                                            END
                                                    END
                                        WHEN c_t.name IN ('datetime2', 'datetimeoffset', 'time')
                                            THEN cast(c.scale AS VARCHAR(4))
                                        WHEN c_t.name IN ('decimal', 'numeric')
                                            THEN cast(c.precision AS VARCHAR(4)) + ', ' + cast(c.scale AS VARCHAR(4))
                                        END + ')', '')
                            FROM sys.columns AS c
                            INNER JOIN sys.types AS c_t
                                ON c.system_type_id = c_t.user_type_id
                            WHERE c.object_id = col.object_id
                                AND c.column_id = col.column_id
                                AND c.user_type_id = col.user_type_id
                            )
                    END -- as data_type_ext,
                , '|'
                , CASE 
                    WHEN col.is_nullable = 0
                        THEN 'N'
                    ELSE 'Y'
                    END -- as nullable,
                , '|'
                , CONVERT(VARCHAR(MAX), ep.value) -- as comments
                , '|'
                )
        FROM sys.VIEWS AS v
        JOIN sys.columns AS col
            ON v.object_id = col.object_id
        LEFT JOIN sys.types AS t
            ON col.user_type_id = t.user_type_id
        LEFT JOIN sys.extended_properties AS ep
            ON v.object_id = ep.major_id
                AND col.column_id = ep.minor_id
                AND ep.name = 'MS_Description'
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        WHERE v.object_id = object_id(CONCAT (
                    @schema_name + '.'
                    , @object_name
                    ))
        ORDER BY schema_name(v.schema_id) -- as schema_name,
            , v.name -- as view_name, 

        -- view code
        INSERT INTO @markdown (line_msg)
        SELECT REPLACE(CONCAT (
                    --'```' + 
                     '```sql' + ' <br/> ' +
                     REPLACE(m.DEFINITION, CHAR(10), ' ```<br/>``` ')
                    , ' ```<br/>'
                    ), '', '')
        FROM sys.VIEWS v
        LEFT JOIN sys.extended_properties ep
            ON v.object_id = ep.major_id
                AND ep.name = 'MS_Description'
                AND ep.minor_id = 0
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        INNER JOIN sys.sql_modules m
            ON m.object_id = v.object_id
        WHERE v.object_id = object_id(CONCAT (
                    @schema_name + '.'
                    , @object_name
                    ))
        ORDER BY schema_name(v.schema_id)
            , v.name;

        -- view dependency graph
        IF EXISTS (
                SELECT NULL
                FROM sys.all_objects tab
                INNER JOIN sys.sql_modules m
                    ON m.DEFINITION LIKE '%' + tab.name + '%'
                WHERE m.object_id = object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                    AND tab.object_id != object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                )
        BEGIN
            INSERT INTO @markdown (line_msg)
            SELECT '```mermaid'

            INSERT INTO @markdown (line_msg)
            SELECT 'graph LR'

            INSERT INTO @markdown (line_msg)
            SELECT DISTINCT CONCAT (
                    @schema_name + '.'
                    , @object_name
                    , ' --> '
                    , schema_name(tab.schema_id) -- as primary_table_schema_name,
                    , '.'
                    , tab.name -- as primary_table_name,
                    )
            FROM sys.all_objects tab
            INNER JOIN sys.sql_modules m
                ON m.DEFINITION LIKE '%' + tab.name + '%'
            WHERE m.object_id = object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))
                AND tab.object_id != object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))

            INSERT INTO @markdown (line_msg)
            SELECT '```'
        END

        FETCH NEXT
        FROM object_cursor
        INTO @schema_name
            , @object_name;
    END;

    CLOSE object_cursor;
    DEALLOCATE object_cursor;

END

-- TRIGGERS SECTION
-- ==============

IF EXISTS (
    SELECT 
        sobj.name AS trigger_name 
        ,USER_NAME(sobj.uid) AS trigger_owner 
        ,s.name AS table_schema 
        ,OBJECT_NAME(parent_obj) AS table_name 
        ,OBJECTPROPERTY( id, 'ExecIsUpdateTrigger') AS on_update 
        ,OBJECTPROPERTY( id, 'ExecIsDeleteTrigger') AS on_delete 
        ,OBJECTPROPERTY( id, 'ExecIsInsertTrigger') AS on_insert
        ,OBJECTPROPERTY( id, 'ExecIsAfterTrigger') AS on_after
        ,OBJECTPROPERTY(id, 'ExecIsTriggerDisabled') AS is_disabled
    FROM sysobjects sobj
        INNER JOIN sys.tables t 
            ON sobj.parent_obj = t.object_id 
        INNER JOIN sys.triggers strig
            ON strig.object_id = OBJECT_ID(sobj.name)
        INNER JOIN sys.schemas s 
            ON t.schema_id = s.schema_id 
    WHERE sobj.type = 'TR' 
        ) AND @enable_triggers = 1
    -- where so.is_ms_shipped = 0 
BEGIN
    INSERT INTO @markdown (line_msg)
    SELECT '## Triggers'

    INSERT INTO @markdown (line_msg)
    SELECT '### Overview'

    INSERT INTO @markdown (line_msg)
    SELECT '|Trigger Name|Used By|On Update|On Delete|On Insert|On After|Is Disabled|'

    INSERT INTO @markdown (line_msg)
    SELECT '|---|---|---|---|---|---|---|---|---|'

    -- triggers overview
    INSERT INTO @markdown (line_msg)
    SELECT CONCAT('|'
        ,USER_NAME(sobj.uid) + '.' + sobj.name,'|'
        ,s.name + '.' + OBJECT_NAME(parent_obj),'|'
        ,IIF(OBJECTPROPERTY(id, 'ExecIsUpdateTrigger')=1,'Y',''),'|'
        ,IIF(OBJECTPROPERTY(id, 'ExecIsDeleteTrigger')=1,'Y',''),'|'
        ,IIF(OBJECTPROPERTY(id, 'ExecIsInsertTrigger')=1,'Y',''),'|'
        ,IIF(OBJECTPROPERTY(id, 'ExecIsAfterTrigger')=1,'Y',''),'|'
        ,IIF(OBJECTPROPERTY(id, 'ExecIsTriggerDisabled')=1,'Y',''),'|')
    FROM sysobjects sobj
        INNER JOIN sys.tables t 
            ON sobj.parent_obj = t.object_id 
        INNER JOIN sys.triggers strig
            ON strig.object_id = OBJECT_ID(sobj.name)
        INNER JOIN sys.schemas s 
            ON t.schema_id = s.schema_id 
    WHERE sobj.type = 'TR' 
    ORDER BY s.name, OBJECT_NAME(parent_obj), sobj.name;
    

    DECLARE object_cursor CURSOR
    FOR
    -- triggers
    SELECT 
         USER_NAME(sobj.uid) as schema_name
        ,sobj.name AS trigger_name
    FROM sysobjects sobj
        INNER JOIN sys.tables t 
            ON sobj.parent_obj = t.object_id 
        INNER JOIN sys.triggers strig
            ON strig.object_id = OBJECT_ID(sobj.name)
        INNER JOIN sys.schemas s 
            ON t.schema_id = s.schema_id 
    WHERE sobj.type = 'TR' 
    ORDER BY s.name, OBJECT_NAME(parent_obj), sobj.name;

    OPEN object_cursor;

    FETCH NEXT
    FROM object_cursor
    INTO @schema_name
        , @object_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- triggers detail
        INSERT INTO @markdown (line_msg)
        SELECT CONCAT (
                '### '
                , @schema_name
                , '.'
                , @object_name
                )

        -- view triggers
        INSERT INTO @markdown (line_msg)
        SELECT REPLACE(CONCAT (
                    --'```' + 
                    '```sql' + ' <br/> ' +
                     REPLACE(m.DEFINITION, CHAR(10), ' ```<br/>``` ')
                    , ' ```<br/>'
                    ), '', '')
        FROM sys.triggers st
            INNER JOIN sys.sql_modules m
            ON st.object_id = m.object_id
        WHERE st.object_id = object_id(CONCAT (
                    @schema_name + '.'
                    , @object_name
                    ))

        -- triggers dependency graph
        IF EXISTS (
                SELECT NULL
                FROM sys.all_objects tab
                INNER JOIN sys.sql_modules m
                    ON m.DEFINITION LIKE '%' + tab.name + '%'
                WHERE m.object_id = object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                    AND tab.object_id != object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                )
        BEGIN
            INSERT INTO @markdown (line_msg)
            SELECT '```mermaid'

            INSERT INTO @markdown (line_msg)
            SELECT 'graph LR'

            INSERT INTO @markdown (line_msg)
            SELECT DISTINCT CONCAT (
                    @schema_name + '.'
                    , @object_name
                    , ' --> '
                    , schema_name(tab.schema_id) -- as primary_table_schema_name,
                    , '.'
                    , tab.name -- as primary_table_name,
                    )
            FROM sys.all_objects tab
            INNER JOIN sys.sql_modules m
                ON m.DEFINITION LIKE '%' + tab.name + '%'
            WHERE m.object_id = object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))
                AND tab.object_id != object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))

            INSERT INTO @markdown (line_msg)
            SELECT '```'
        END

        FETCH NEXT
        FROM object_cursor
        INTO @schema_name
            , @object_name;
    END;

    CLOSE object_cursor;
    DEALLOCATE object_cursor;

END

-- PROGRAMMING SECTION
-- ==============

IF EXISTS (
        SELECT NULL
        FROM sys.sql_modules m
        INNER JOIN sys.all_objects so
            ON so.object_id = m.object_id
        LEFT JOIN sys.extended_properties AS ep
            ON so.object_id = ep.major_id
                AND ep.name = 'MS_Description'
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        ) AND @enable_procs = 1
    -- where so.is_ms_shipped = 0 
BEGIN
    INSERT INTO @markdown (line_msg)
    SELECT '## Programming'

    INSERT INTO @markdown (line_msg)
    SELECT '### Overview'

    INSERT INTO @markdown (line_msg)
    SELECT '|type|script schema|script name|created date|modified date|description|'

    INSERT INTO @markdown (line_msg)
    SELECT '|---|---|---|---|---|---|'

    -- programming overview
    INSERT INTO @markdown (line_msg)
    SELECT CONCAT (
            '|'
            , so.type_desc
            , '|'
            , schema_name(so.schema_id)
            , '|'
            , so.name
            , '|'
            , FORMAT(so.create_date, 'yyyy-MM-dd')
            , '|'
            , FORMAT(so.modify_date, 'yyyy-MM-dd')
            -- , '|' , m.definition
            , '|'
            , CONVERT(VARCHAR(MAX), ep.value)
            , '|'
            )
    FROM sys.sql_modules m
    INNER JOIN sys.all_objects so
        ON so.object_id = m.object_id
    LEFT JOIN sys.extended_properties AS ep
        ON so.object_id = ep.major_id
            AND ep.name = 'MS_Description'
            AND ep.class_desc = 'OBJECT_OR_COLUMN'
    WHERE so.type_desc NOT IN('VIEW','TR')
    ORDER BY so.type_desc
        , schema_name(so.schema_id)
        , so.name;

    DECLARE object_cursor CURSOR
    FOR
    -- programming
    SELECT schema_name(so.schema_id)
        , so.name
    FROM sys.sql_modules m
    INNER JOIN sys.all_objects so
        ON so.object_id = m.object_id
    LEFT JOIN sys.extended_properties AS ep
        ON so.object_id = ep.major_id
            AND ep.name = 'MS_Description'
            AND ep.class_desc = 'OBJECT_OR_COLUMN'
    WHERE so.type_desc NOT IN('VIEW','TR')
    ORDER BY schema_name(so.schema_id)
        , so.type_desc
        , so.name;

    OPEN object_cursor;

    FETCH NEXT
    FROM object_cursor
    INTO @schema_name
        , @object_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- programming detail
        INSERT INTO @markdown (line_msg)
        SELECT CONCAT (
                '### '
                , @schema_name
                , '.'
                , @object_name
                )

        -- view programming
        INSERT INTO @markdown (line_msg)
        SELECT REPLACE(CONCAT (
                    --'```' + 
                     '```sql' + ' <br/> ' +
                     REPLACE(IIF(LENGTH(m.DEFINITION)>7000,SUBTRING(m.DEFINITION,1,7000)+' [...TRUNCATED...] ',m.DEFINITION), CHAR(10), ' ```<br/>``` ')
                    , ' ```<br/>'
                    ), '', '')
        FROM sys.sql_modules m
        INNER JOIN sys.all_objects so
            ON so.object_id = m.object_id
        LEFT JOIN sys.extended_properties AS ep
            ON so.object_id = ep.major_id
                AND ep.name = 'MS_Description'
                AND ep.class_desc = 'OBJECT_OR_COLUMN'
        WHERE so.object_id = object_id(CONCAT (
                    @schema_name + '.'
                    , @object_name
                    ))
            AND so.type_desc NOT IN('VIEW','TR')
        ORDER BY schema_name(so.schema_id)
            , so.type_desc
            , so.name;

        -- programming dependency graph
        IF EXISTS (
                SELECT NULL
                FROM sys.all_objects tab
                INNER JOIN sys.sql_modules m
                    ON m.DEFINITION LIKE '%' + tab.name + '%'
                WHERE m.object_id = object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                    AND tab.object_id != object_id(CONCAT (
                            @schema_name + '.'
                            , @object_name
                            ))
                )
        BEGIN
            INSERT INTO @markdown (line_msg)
            SELECT '```mermaid'

            INSERT INTO @markdown (line_msg)
            SELECT 'graph LR'

            INSERT INTO @markdown (line_msg)
            SELECT DISTINCT CONCAT (
                    @schema_name + '.'
                    , @object_name
                    , ' --> '
                    , schema_name(tab.schema_id) -- as primary_table_schema_name,
                    , '.'
                    , tab.name -- as primary_table_name,
                    )
            FROM sys.all_objects tab
            INNER JOIN sys.sql_modules m
                ON m.DEFINITION LIKE '%' + tab.name + '%'
            WHERE m.object_id = object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))
                AND tab.object_id != object_id(CONCAT (
                        @schema_name + '.'
                        , @object_name
                        ))

            INSERT INTO @markdown (line_msg)
            SELECT '```'
        END

        FETCH NEXT
        FROM object_cursor
        INTO @schema_name
            , @object_name;
    END;

    CLOSE object_cursor;
    DEALLOCATE object_cursor;
    
END

-- OUTPUT RESULTS
SELECT line_msg
FROM @markdown
ORDER BY line_no ASC;
