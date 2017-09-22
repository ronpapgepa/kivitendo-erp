-- @tag: shop_3
-- @description: Add columns itime and transaction_description for table shops
-- @charset: UTF-8
-- @depends: shops
-- @ignore: 0

ALTER TABLE shops ADD COLUMN transaction_description TEXT;
ALTER TABLE shops ADD COLUMN itime timestamp DEFAULT now();
