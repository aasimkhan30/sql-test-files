SELECT TOP 1
    CONCAT(
        '{ "id": ', ABS(CHECKSUM(NEWID())) % 1000,
        ', "value": "', NEWID(),
        '", "flag": ', ABS(CHECKSUM(NEWID())) % 2,
        ' }'
    ) AS RandomJson;
