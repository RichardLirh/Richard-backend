package richard.modules.knowledge.dao;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import richard.common.dao.BaseDao;
import richard.modules.knowledge.entity.KnowledgeBaseEntity;

/**
 * 知识库知识库
 */
@Mapper
public interface KnowledgeBaseDao extends BaseDao<KnowledgeBaseEntity> {

    /**
     * 根据知识库ID删除相关的插件映射记录
     * 
     * @param knowledgeBaseId 知识库ID
     */
    void deletePluginMappingByKnowledgeBaseId(@Param("knowledgeBaseId") String knowledgeBaseId);

}