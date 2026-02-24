package richard.modules.agent.vo;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.extension.handlers.JacksonTypeHandler;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;
import lombok.EqualsAndHashCode;
import richard.modules.agent.dto.ContextProviderDTO;
import richard.modules.agent.entity.AgentEntity;
import richard.modules.agent.entity.AgentPluginMapping;

import java.util.List;

/**
 * Agent信息返回体VO
 * 这里直接extend了Agent实体类AgentEntity，后续需要规范返回字段可以copy字段出来
 */
@EqualsAndHashCode(callSuper = true)
@Data
public class AgentInfoVO extends AgentEntity
{
    @Schema(description = "插件列表Id")
    @TableField(typeHandler = JacksonTypeHandler.class)
    private List<AgentPluginMapping> functions;

    @Schema(description = "上下文源配置")
    private List<ContextProviderDTO> contextProviders;
}
