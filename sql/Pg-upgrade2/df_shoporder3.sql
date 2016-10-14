-- @tag: df_shoporder3
-- @description: Feld df_kivi_customer_order_lock in der shoporder Tabelle wieder gelösch da order_lock direkt aus den Kundendaten genommen wird. Tabellen customer und shop_order sind Verknüpft. Spalte obsolete hinzgefügt
-- @depends: release_3_4_0

ALTER TABLE shop_orders DROP COLUMN df_kivi_customer_order_lock;
ALTER TABLE shop_orders ADD COLUMN obsolete boolean DEFAULT FALSE NOT NULL;
