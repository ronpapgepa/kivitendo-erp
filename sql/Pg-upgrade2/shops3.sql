-- @tag: shops3
-- @description: Alter table shops more columns for configuration
-- @charset: UTF-8
-- @depends: release_3_4_0 shops
-- @ignore: 0

ALTER TABLE shops ADD COLUMN taxzone_id integer;
