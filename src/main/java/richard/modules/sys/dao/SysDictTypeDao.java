package richard.modules.sys.dao;

import org.apache.ibatis.annotations.Mapper;

import richard.common.dao.BaseDao;
import richard.modules.sys.entity.SysDictTypeEntity;

/**
 * 字典类型
 */
@Mapper
public interface SysDictTypeDao extends BaseDao<SysDictTypeEntity> {

}
