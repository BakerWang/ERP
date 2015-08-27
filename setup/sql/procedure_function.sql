---------------------------------------------
-- Export file for user ERP                --
-- Created by 21829 on 2015/5/19, 20:34:08 --
---------------------------------------------

set define off
spool procedure_function.log

prompt
prompt Creating function GETRELEASEBOMBYPRODUCTID
prompt ==========================================
prompt
create or replace function erp.getReleaseBOMByProductId(v_productId number)
  return number is
  retId     number;
  productId number;
  --���ݲ�Ʒ�ı�Ų�ѯ���·�������˹��Ľṹid
begin
  productId := v_productId;
  if (productId is not null) then
    select t.ID
      into retId
    --t.PRODUCTS_ID, t.DESCR, t.EFFDT, t.EFF_STATUS
      from T_BOM_PRIMARY t
     where t.EFF_STATUS = '1'
       and t.effdt < to_char(sysdate, 'yyyy-mm-dd hh24:mi:ss')
       and t.PRODUCTS_ID = productId
       and rownum = 1
     order by t.EFFDT desc;
  end if;
  return(retId);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    --retId:='';
    --When Others Then
    --retId:='';
    return(retId);
end getReleaseBOMByProductId;
/

prompt
prompt Creating procedure EXPAND_PRODUCT_BOM
prompt =====================================
prompt
create or replace procedure erp.EXPAND_PRODUCT_BOM(V_SALES_ORDER_ID  IN NUMBER,
                                               V_PRODUCT_ID      IN NUMBER,
                                               V_IS_MAIN_PRODUCT IN NUMBER,
                                               V_TIER            IN NUMBER,
                                               --V_QTY             IN NUMBER,
                                               V_PARENT_ID IN NUMBER) as
begin
  declare
    SALES_ORDER_ID  number; -- ���۶������
    PRODUCT_ID      number; -- ��Ʒ���
    IS_MAIN_PRODUCT number; -- �Ƿ���Ҫ��Ʒ��ֻչ����һ��Ϊ׼��
    TIER            number; -- �㼶����Ʒ����Ϊ0��
    QTY             number; -- ����
    PARENT_ID       number; -- �����id
  
    SOURCE_TYPE    varchar2(50); -- ��Դ,��ɹ�(120)����ӹ�(122)��������(121)
    insert_id      number; -- ��Ʒid
    temp_parent_id number; -- �ݴ��parent_id
  
    bom_primary_id number; -- ��Ʒ�ṹ�е�����id
  
    sub_count number; -- ����ϵ�����
  begin
    SALES_ORDER_ID  := V_SALES_ORDER_ID;
    PRODUCT_ID      := V_PRODUCT_ID;
    IS_MAIN_PRODUCT := V_IS_MAIN_PRODUCT;
    TIER            := V_TIER;
    --QTY             := V_QTY;
    PARENT_ID := V_PARENT_ID;
  
    select t.source_type
      into SOURCE_TYPE
      from T_PRODUCTS t
     where t.id = PRODUCT_ID;
  
    dbms_output.put_line('EXPAND_PRODUCT_BOM');
    /**
    * 1���������ݿ�,���ݲ㼶�ж�
    * 2���ж����ϡ�����ϵĹ�ϵ
    * 3���жϲ�Ʒ��Դ�Ƿ���<������>������ǣ���ݹ�����Լ�
    *
    */
  
    -- �������ĵݹ����,������ѭ�������������㼶��Լ100���򲻼����ݹ�
    if (SOURCE_TYPE is not null and SOURCE_TYPE = 121 and TIER < 100) then
      -- ���ݲ�Ʒ����ҵ��ṹ�����primary_id
      bom_primary_id := getReleaseBOMByProductId(PRODUCT_ID);
      --�ҵ���Ʒ�ṹ
      if (bom_primary_id is not null) then
        --������Ʒ�ṹ������ָ���Ĳ���
        for p in (select t.id,
                         t.primary_id,
                         t.sub_products_id,
                         t.is_main_products,
                         t.qty
                    from t_bom_detail t
                   where t.primary_id = bom_primary_id) loop
        
          select decode(TIER, 1, p.is_main_products, IS_MAIN_PRODUCT)
            into IS_MAIN_PRODUCT
            from dual;
        
          -- dbms_output.put_line(p.id);
          -- ���Ҳ�Ʒ����Դ,��ɹ�(120)����ӹ�(122)��������(121)
          select t.source_type
            into SOURCE_TYPE
            from T_PRODUCTS t
           where t.id = p.sub_products_id;
          -- ��Ҫ�����ID
          select SEQUENCE_T_SALES_ORDER_BOM.nextval
            into insert_id
            from dual;
        
          -- ��ѯ�Ƿ������ϡ������
          select count(1)
            into sub_count
            from T_BOM_SUB t
           where t.primary_id = p.primary_id
             and t.main_products_id = p.sub_products_id;
        
          --�㼶Ϊ1��ʱ��,��Ҫ��ȡ[�Ƿ�Ϊ��Ҫ����]ֵ,�������ϡ������,parentId
          --�̳�[�Ƿ�����Ҫ����],�������ϡ������,parentId
          insert into T_SALES_ORDER_BOM
            (ID,
             ORDER_ID,
             PRODUCTS_ID,
             QTY,
             TIER,
             SOURCE_TYPE,
             PARENT_ID,
             IS_MAIN_PRODUCTS,
             MAIN_SUB)
          values
            (insert_id,
             SALES_ORDER_ID,
             p.sub_products_id,
             p.qty,
             TIER,
             SOURCE_TYPE,
             PARENT_ID,
             IS_MAIN_PRODUCT,
             decode(sub_count, 0, '', 'Y'));
          commit;
          --dbms_output.put_line(2);
        
          temp_parent_id := insert_id;
        
          --��������
          if (sub_count is not null and sub_count > 0) then
            for sub in (select t.sub_products_id,
                               t.qty,
                               t.primary_id,
                               t.main_products_id
                          from T_BOM_SUB t
                         where t.primary_id = p.primary_id
                           and t.main_products_id = p.sub_products_id) loop
            
              -- ��Ʒ��Դ                  
              select t.source_type
                into SOURCE_TYPE
                from T_PRODUCTS t
               where t.id = sub.sub_products_id;
              -- ��Ҫ�����ID
              select SEQUENCE_T_SALES_ORDER_BOM.nextval
                into insert_id
                from dual;
            
              --���������   
              insert into T_SALES_ORDER_BOM
                (ID,
                 ORDER_ID,
                 PRODUCTS_ID,
                 QTY,
                 TIER,
                 SOURCE_TYPE,
                 PARENT_ID,
                 IS_MAIN_PRODUCTS,
                 MAIN_PRODUCTS_ID,
                 MAIN_SUB)
              values
                (insert_id,
                 SALES_ORDER_ID,
                 sub.sub_products_id,
                 sub.qty,
                 TIER,
                 SOURCE_TYPE,
                 PARENT_ID,
                 IS_MAIN_PRODUCT,
                 sub.main_products_id,
                 'N');
              commit;
            
            end loop;
          end if;
        
          --�ݹ���ô洢���̣�չ����Ʒ
          EXPAND_PRODUCT_BOM(SALES_ORDER_ID,
                             p.sub_products_id,
                             IS_MAIN_PRODUCT,
                             TIER + 1,
                             temp_parent_id);
        
        end loop;
      end if;
    
    end if;
  end;
end EXPAND_PRODUCT_BOM;
/

prompt
prompt Creating procedure EXPAND_SALES_ORDER_BOM
prompt =========================================
prompt
create or replace procedure erp.expand_sales_order_bom(sales_order_id in number) as
begin
  declare
    --count_products number;
    input_id    number;
    SOURCE_TYPE varchar2(50); -- ��Դ,��ɹ�(120)����ӹ�(122)��������(121)
    insert_id   number; -- ��Ʒid
  begin
    input_id := sales_order_id;
    --��ѯ���۶����еĲ�Ʒ��ϸ
    for so in (select t.id,
                      t.sales_order_id, -- ���۶���id
                      t.products_id, -- ��Ʒ���
                      t.storage_number --����
                 from T_SALES_ORDER_DETAIL t
                where t.sales_order_id = input_id) loop
      dbms_output.put_line(so.id || ' : ' || so.sales_order_id || ' : ' ||
                           so.products_id);
    
      select SEQUENCE_T_SALES_ORDER_BOM.nextval into insert_id from dual;
    
      select t.source_type
        into SOURCE_TYPE
        from T_PRODUCTS t
       where t.id = so.products_id;
       
      --���붥���Ĳ�Ʒ
      insert into T_SALES_ORDER_BOM
        (ID, ORDER_ID, PRODUCTS_ID, QTY, TIER, SOURCE_TYPE)
      values
        (insert_id,
         so.sales_order_id,
         so.products_id,
         so.storage_number,
         0,
         SOURCE_TYPE);
       commit;  
      --չ����ÿ����Ʒ                       
      EXPAND_PRODUCT_BOM(so.sales_order_id,
                         so.products_id,
                         '',
                         1,
                         --so.storage_number,
                         insert_id);
    end loop;
  end;
end expand_sales_order_bom;
/


prompt
prompt Creating ������ת������������
prompt =========================================
prompt
drop  procedure erp.task_Production_task;

create or replace procedure erp.task_Production_task(v_ProcessingSingleID number) as
begin
declare
       t_processingSingleID  number; -- ������id
       t_status number;
       task_id number;
       task_detail_id number;
       t_dateChar char(8);
begin
        t_processingSingleID  := v_ProcessingSingleID;

    select t.status  into t_status from t_processing_single_primary t where t.id= t_processingSingleID;
    select to_char(sysdate,'yyyymmdd') into t_dateChar from dual;
        if(t_status = 1) then
           dbms_output.PUT_LINE('������������');
           for sub in (select startdate, enddate
  from t_processing_single_detail t
 where t.processingsingleid = t_processingSingleID
 group by processingsingleid, startdate, enddate) loop
             dbms_output.PUT_LINE(sub.startdate);
             select SEQUENCE_T_ProductionTask.nextval into task_id from dual;
             insert into T_ProductionTask (ID,Production_order,Inventory_countID,STARTDATE,ENDDATE) values (task_id,'SCD' || t_dateChar || task_id ,t_processingSingleID,sub.startdate,sub.enddate);
             for task in ( select products_id,processingnumber from t_processing_single_detail t where t.processingsingleid=t_processingSingleID and startdate=sub.startdate and enddate=sub.enddate) loop
               select SEQUENCE_T_Production_DETAIL.nextval into task_detail_id from dual;
               insert into T_PRODUCTIONTASK_DETAIL (id,productiontaskid,products_id,processingnumber)values(task_detail_id,task_id,task.products_id,task.processingnumber);
             end loop;
           end loop;
        else
           dbms_output.PUT_LINE('�Ѿ�������������');
        end if;
        commit;
end;
end task_Production_task;
/

spool off
