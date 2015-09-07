--------------------------------------------
-- Export file for user ERP               --
-- Created by 21829 on 2015/9/7, 19:52:50 --
--------------------------------------------

set define off
spool procedure_function.log

prompt
prompt Creating procedure EXPAND_PRODUCT_BOM
prompt =====================================
prompt
create or replace procedure erp.EXPAND_PRODUCT_BOM(V_SALES_ORDER_ID  IN NUMBER,
                                               V_PRODUCT_ID      IN NUMBER,
                                               V_IS_MAIN_PRODUCT IN NUMBER,
                                               V_TIER            IN NUMBER,
                                               V_QTY             IN NUMBER,
                                               V_PARENT_ID IN NUMBER) as
begin
  declare
    SALES_ORDER_ID  number; -- 销售订单编号
    PRODUCT_ID      number; -- 产品编号
    IS_MAIN_PRODUCT number; -- 是否主要产品（只展开第一成为准）
    TIER            number; -- 层级（产品本身为0）
    QTY             number; -- 数量
    PARENT_ID       number; -- 父类的id
    
    bom_qty        number; -- 数量
    bom_sub_qty    number; -- 数量
    scrap_factor   float; --损耗率
  
    SOURCE_TYPE    varchar2(50); -- 来源,如采购(120)，外加工(122)，自生产(121)
    insert_id      number; -- 产品id
    temp_parent_id number; -- 暂存的parent_id
  
    bom_primary_id number; -- 产品结构中的主表id
    
    bom_sub_primary_id number; -- 产品结构中的主表id
  
    sub_count number; -- 替代料的数量
  begin
    SALES_ORDER_ID  := V_SALES_ORDER_ID;
    PRODUCT_ID      := V_PRODUCT_ID;
    IS_MAIN_PRODUCT := V_IS_MAIN_PRODUCT;
    TIER            := V_TIER;
    QTY             := V_QTY;
    PARENT_ID := V_PARENT_ID;
  
    select t.source_type
      into SOURCE_TYPE
      from T_PRODUCTS t
     where t.id = PRODUCT_ID;
     
    select t.scrap_factor into scrap_factor from sys_param t ;
  
    dbms_output.put_line('EXPAND_PRODUCT_BOM');
    /**
    * 1、插入数据库,根据层级判断
    * 2、判断主料、替代料的关系
    * 3、判断产品来源是否是<自生产>，如果是，则递归调用自己
    *
    */
  
    -- 自生产的递归调用,考虑死循环的情况，如果层级大约100，则不继续递归
    if (SOURCE_TYPE is not null and SOURCE_TYPE = 121 and TIER < 100) then
      -- 根据产品编号找到结构主表的primary_id
      bom_primary_id := getReleaseBOMByProductId(PRODUCT_ID);
      --找到产品结构
      if (bom_primary_id is not null) then
        --迭代产品结构，进行指定的操作
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
            
          select decode(TIER, 1, round(p.qty * QTY * (1+scrap_factor)), p.qty * QTY)
            into bom_qty
            from dual;
        
          -- dbms_output.put_line(p.id);
          -- 查找产品的来源,如采购(120)，外加工(122)，自生产(121)
          select t.source_type
            into SOURCE_TYPE
            from T_PRODUCTS t
           where t.id = p.sub_products_id;
          -- 需要插入的ID
          select SEQUENCE_T_SALES_ORDER_BOM.nextval
            into insert_id
            from dual;
        
          -- 查询是否有主料、替代料
          select count(1)
            into sub_count
            from T_BOM_SUB t
           where t.primary_id = p.primary_id
             and t.main_products_id = p.sub_products_id;
             
          --获取产品结构id
          bom_sub_primary_id := getReleaseBOMByProductId(p.sub_products_id);
          
           
        
          --层级为1的时候,需要获取[是否为主要材料]值,计算主料、替代料,parentId
          --继承[是否是主要材料],计算主料、替代料,parentId
          insert into T_SALES_ORDER_BOM
            (ID,
             ORDER_ID,
             PRODUCTS_ID,
             PRODUCTS_BOM_ID,
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
             bom_sub_primary_id,
             --p.qty*QTY,
             bom_qty,
             TIER,
             SOURCE_TYPE,
             PARENT_ID,
             IS_MAIN_PRODUCT,
             decode(sub_count, 0, '', 'Y'));
          commit;
          --dbms_output.put_line(2);
        
          temp_parent_id := insert_id;
        
          --添加替代料
          if (sub_count is not null and sub_count > 0) then
            for sub in (select t.sub_products_id,
                               t.qty,
                               t.primary_id,
                               t.main_products_id
                          from T_BOM_SUB t
                         where t.primary_id = p.primary_id
                           and t.main_products_id = p.sub_products_id) loop
            
              -- 产品来源                  
              select t.source_type
                into SOURCE_TYPE
                from T_PRODUCTS t
               where t.id = sub.sub_products_id;
              -- 需要插入的ID
              select SEQUENCE_T_SALES_ORDER_BOM.nextval
                into insert_id
                from dual;
                
          select decode(TIER, 1, round(sub.qty * QTY * (1+scrap_factor)), sub.qty * QTY)
            into bom_sub_qty
            from dual;
            
              --插入替代料   
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
                 --sub.qty*QTY,
                 bom_sub_qty,
                 TIER,
                 SOURCE_TYPE,
                 PARENT_ID,
                 IS_MAIN_PRODUCT,
                 sub.main_products_id,
                 'N');
              commit;
            
            end loop;
          end if;
        
          --递归调用存储过程，展开产品
          EXPAND_PRODUCT_BOM(SALES_ORDER_ID,
                             p.sub_products_id,
                             IS_MAIN_PRODUCT,
                             TIER + 1,
                             p.qty*QTY,
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
    SOURCE_TYPE varchar2(50); -- 来源,如采购(120)，外加工(122)，自生产(121)
    insert_id   number; -- 产品id
    bom_primary_id number; -- 产品结构中的主表id
  begin
    input_id := sales_order_id;
    --查询销售订单中的产品明细
    for so in (select t.id,
                      t.sales_order_id, -- 销售订单id
                      t.products_id, -- 产品编号
                      t.storage_number --数量
                 from T_SALES_ORDER_DETAIL t
                where t.sales_order_id = input_id) loop
      dbms_output.put_line(so.id || ' : ' || so.sales_order_id || ' : ' ||
                           so.products_id);
    
      select SEQUENCE_T_SALES_ORDER_BOM.nextval into insert_id from dual;
    
      select t.source_type
        into SOURCE_TYPE
        from T_PRODUCTS t
       where t.id = so.products_id;
       
       bom_primary_id := getReleaseBOMByProductId(so.products_id);
       
      --插入顶级的产品
      insert into T_SALES_ORDER_BOM
        (ID, ORDER_ID, PRODUCTS_ID,PRODUCTS_BOM_ID, QTY, TIER, SOURCE_TYPE)
      values
        (insert_id,
         so.sales_order_id,
         so.products_id,
         bom_primary_id,
         so.storage_number,
         0,
         SOURCE_TYPE);
       commit;  
      --展开的每个产品                       
      EXPAND_PRODUCT_BOM(so.sales_order_id,
                         so.products_id,
                         '',
                         1,
                         so.storage_number,
                         insert_id);
    end loop;
  end;
end expand_sales_order_bom;
/

prompt
prompt Creating 任务单自动生成加工任务单和验收单
prompt =========================================
prompt
create or replace procedure erp.task_Production_task(v_ProcessingSingleID number) as
begin
declare
       t_processingSingleID  number; -- 生产单id
       t_status number;
       task_id number;
       task_detail_id number;
       acceptanceList_id number;
       t_dateChar char(8);
       bomPrimaryID number;
       order_id number;
       --processStr varcahr(500);
begin
        t_processingSingleID  := v_ProcessingSingleID;

    select t.status,purchase_order_id  into t_status, order_id from t_processing_single_primary t where t.id= t_processingSingleID;
    select to_char(sysdate,'yyyymmdd') into t_dateChar from dual;
        if(t_status = 1) then
           dbms_output.PUT_LINE('生成生产任务单');
           for sub in (select processingsingleid,startdate, enddate
  from t_processing_single_detail t
 where t.processingsingleid = t_processingSingleID
 group by processingsingleid, startdate, enddate) loop
             dbms_output.PUT_LINE(sub.startdate);
             select SEQUENCE_T_ProductionTask.nextval into task_id from dual;
             insert into T_ProductionTask (ID,Production_order,Inventory_countID,STARTDATE,ENDDATE) values (task_id,'SCD' || t_dateChar || task_id ,t_processingSingleID,sub.startdate,sub.enddate);
             for task in ( select products_id,processingnumber from t_processing_single_detail t where t.processingsingleid=t_processingSingleID and startdate=sub.startdate and enddate=sub.enddate) loop
               select SEQUENCE_T_Production_DETAIL.nextval into task_detail_id from dual;
               insert into T_PRODUCTIONTASK_DETAIL (id,productiontaskid,products_id,processingnumber)values(task_detail_id,task_id,task.products_id,task.processingnumber);

               --获取产品结构主键
               select products_bom_id into bomPrimaryID from (select products_bom_id from T_SALES_ORDER_BOM where products_id=task.products_id and order_id=order_id) where rownum = 1;

               for process in (select pr.process_id,ce.name,pr.remarks from T_PRODUCTPROCESS pr left join t_process ce on pr.process_id=ce.id where pr.bomprimary_id=bomPrimaryID) loop
                  select SEQUENCE_T_AcceptanceList.nextval into acceptanceList_id from dual;
                  insert into T_AcceptanceList (id,productiontaskid,products_id,processid,Isacceptance)values(acceptanceList_id,task_id,task.products_id,process.process_id,'0');
               end loop;
             end loop;
           end loop;
        else
           dbms_output.PUT_LINE('已经存在生产任务单');
        end if;
        commit;
end;
end task_Production_task;
/
spool off
