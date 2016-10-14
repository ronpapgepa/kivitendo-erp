-- @tag: df_shoporder
-- @description: Feld Auftragssperre in der shoporder Tabelle
-- @depends: release_3_4_0

ALTER TABLE shop_orders ADD COLUMN df_kivi_customer_order_lock boolean DEFAULT FALSE NOT NULL;
