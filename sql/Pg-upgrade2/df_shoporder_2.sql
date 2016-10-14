-- @tag: df_shoporder_2
-- @description: Feld Positionen in der shoporder Tabelle
-- @depends: release_3_4_0

ALTER TABLE shop_orders ADD COLUMN positions integer;

