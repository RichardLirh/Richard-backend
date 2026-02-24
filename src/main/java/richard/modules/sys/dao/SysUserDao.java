package richard.modules.sys.dao;

import org.apache.ibatis.annotations.Mapper;

import richard.common.dao.BaseDao;
import richard.modules.sys.entity.SysUserEntity;

/**
 * 系统用户
 */
@Mapper
public interface SysUserDao extends BaseDao<SysUserEntity> {

}